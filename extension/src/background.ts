import browser from 'webextension-polyfill';
import {
  deriveSnapshot,
  detectChatGPTPlan,
  fetchExactChatGPTSnapshot,
  pruneEvents,
  type ChatGPTMessageEvent,
} from './chatgpt';
import { AuthError, fetchClaudeUsage, RateLimitError } from './claude';
import { AuthError as MJAuthError, fetchMidjourneyUsage, RateLimitError as MJRateLimitError } from './midjourney';
import { AuthError as ELAuthError, fetchElevenLabsUsage, RateLimitError as ELRateLimitError } from './elevenlabs';
import { AuthError as GrokAuthError, fetchGrokUsage, RateLimitError as GrokRateLimitError } from './grok';
import { AuthError as PxAuthError, fetchPerplexityUsage, RateLimitError as PxRateLimitError } from './perplexity';
import { AuthError as LeoAuthError, fetchLeonardoUsage, RateLimitError as LeoRateLimitError } from './leonardo';
import type { ExtensionMessage, ExtensionResponse } from './messages';
import type { ProviderUsageSnapshot } from './snapshot';
import { sendBridgeBatch, scheduleBridgeSend, registerRefreshWebProvidersHandler } from './bridge';
import {
  getBackoff,
  getChatGPTEvents,
  getChatGPTPlanEffective,
  getChatGPTSnapshot,
  getClaudeSnapshot,
  getGeminiConsumerSnapshot,
  getMidjourneyBackoff,
  getMidjourneySnapshot,
  getPinnedProvider,
  setBackoff,
  setChatGPTEvents,
  setChatGPTPlanAuto,
  setChatGPTPlanOverride,
  setChatGPTSnapshot,
  setClaudeAuth,
  setClaudeSnapshot,
  setGeminiConsumerSnapshot,
  setMidjourneyAuth,
  setMidjourneyBackoff,
  setMidjourneySnapshot,
  getElevenLabsBackoff,
  getElevenLabsSnapshot,
  setElevenLabsAuth,
  setElevenLabsBackoff,
  setElevenLabsSnapshot,
  getElevenLabsFirebaseToken,
  setElevenLabsFirebaseToken,
  getGrokBackoff,
  getGrokSnapshot,
  setGrokAuth,
  setGrokBackoff,
  setGrokSnapshot,
  getPerplexityBackoff,
  getPerplexitySnapshot,
  setPerplexityAuth,
  setPerplexityBackoff,
  setPerplexitySnapshot,
  getPerplexityCaps,
  setPerplexityCaps,
  getLeonardoBackoff,
  getLeonardoSnapshot,
  setLeonardoAuth,
  setLeonardoBackoff,
  setLeonardoSnapshot,
  getLeonardoCredentials,
  setLeonardoCredentials,
} from './storage';
import type { ProviderId } from './types';

const CLAUDE_ALARM = 'claude-poll';
const MIDJOURNEY_ALARM = 'midjourney-poll';
const ELEVENLABS_ALARM = 'elevenlabs-poll';
const GROK_ALARM = 'grok-poll';
const PERPLEXITY_ALARM = 'perplexity-poll';
const LEONARDO_ALARM = 'leonardo-poll';
const PLAN_REDETECT_ALARM = 'chatgpt-plan-redetect';
const BRIDGE_HEARTBEAT_ALARM = 'bridgeHeartbeat';
const POLL_PERIOD_MIN = 5;
const MIDJOURNEY_POLL_PERIOD_MIN = 10; // less frequent — billing data changes slowly
const ELEVENLABS_POLL_PERIOD_MIN = 10; // monthly billing window, no need to poll rapidly
const GROK_POLL_PERIOD_MIN = 5;        // daily rolling window — poll at standard cadence
const PERPLEXITY_POLL_PERIOD_MIN = 5;  // daily window
const LEONARDO_POLL_PERIOD_MIN = 10;   // token balance changes slowly; gated on cached creds
const PLAN_REDETECT_PERIOD_MIN = 60 * 24; // re-check plan once a day

// Exponential backoff: 5m → 10m → 20m → 40m → 60m (cap)
const BACKOFF_INITIAL_MS = 5 * 60_000;
const BACKOFF_MAX_MS = 60 * 60_000;

console.log('[tokenomics] service worker booted');

// Register the command handler so bridge.ts can trigger re-polls without
// importing background.ts (which would create a circular dependency).
registerRefreshWebProvidersHandler(() => {
  void pollClaude('manual');
  void pollMidjourney('manual');
  void pollElevenLabs('manual');
  void pollGrok('manual');
  void pollPerplexity('manual');
  void pollLeonardo('manual');
  void recomputeChatGPTSnapshot();
  // geminiConsumer is content-script-driven — no manual re-fetch available.
  // leonardo re-fetches from cached creds (skips silently if none yet).
});

void sendBridgeBatch('ping').catch(() => undefined);

browser.runtime.onInstalled.addListener(async () => {
  await scheduleAlarms();
  void pollClaude('install');
  void pollMidjourney('install');
  void pollElevenLabs('install');
  void pollGrok('install');
  void pollPerplexity('install');
  void pollLeonardo('install');
  void redetectChatGPTPlan('install');
});

browser.runtime.onStartup.addListener(async () => {
  await scheduleAlarms();
});

browser.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === CLAUDE_ALARM) void pollClaude('alarm');
  else if (alarm.name === MIDJOURNEY_ALARM) void pollMidjourney('alarm');
  else if (alarm.name === ELEVENLABS_ALARM) void pollElevenLabs('alarm');
  else if (alarm.name === GROK_ALARM) void pollGrok('alarm');
  else if (alarm.name === PERPLEXITY_ALARM) void pollPerplexity('alarm');
  else if (alarm.name === LEONARDO_ALARM) void pollLeonardo('alarm');
  else if (alarm.name === PLAN_REDETECT_ALARM) void redetectChatGPTPlan('alarm');
  else if (alarm.name === BRIDGE_HEARTBEAT_ALARM) void sendBridgeBatch('heartbeat').catch(() => undefined);
});

browser.storage.onChanged.addListener((changes, area) => {
  if (area !== 'local') return;
  if ('pinnedProvider' in changes) void updateBadge();
  if ('chatgptPlanOverride' in changes || 'chatgptPlanAuto' in changes) {
    void recomputeChatGPTSnapshot();
  }
});

browser.runtime.onMessage.addListener(
  async (message: unknown): Promise<ExtensionResponse | undefined> => {
    const msg = message as ExtensionMessage | undefined;
    if (!msg) return undefined;

    if (msg.kind === 'GEMINI_USAGE') {
      // Snapshot was parsed in the content script and relayed here.
      await setGeminiConsumerSnapshot(msg.snapshot);
      scheduleBridgeSend('snapshot');
      await updateBadge();
      console.log('[tokenomics] gemini consumer snapshot received', msg.snapshot);
      return { kind: 'ACK' };
    }

    if (msg.kind === 'ELEVENLABS_TOKEN') {
      // Firebase token from the elevenlabs-grab content script. Cache it and
      // immediately trigger a usage poll with the fresh token.
      await setElevenLabsFirebaseToken(msg.token);
      console.log('[tokenomics] elevenlabs firebase token received — triggering poll');
      void pollElevenLabs('manual');
      return { kind: 'ACK' };
    }

    if (msg.kind === 'LEONARDO_TOKEN') {
      // Cognito credentials from the leonardo-grab content script. Cache and poll.
      await setLeonardoCredentials(msg.idToken, msg.userSub);
      console.log('[tokenomics] leonardo cognito token received — triggering poll');
      void pollLeonardo('manual');
      return { kind: 'ACK' };
    }

    if (msg.kind === 'CHATGPT_MESSAGE') {
      await recordChatGPTMessage(msg.model, msg.ts);
      return { kind: 'ACK' };
    }

    if (msg.kind === 'CHATGPT_SET_PLAN') {
      if (msg.plan === 'auto') {
        await setChatGPTPlanOverride(null);
        await redetectChatGPTPlan('manual');
      } else {
        await setChatGPTPlanOverride(msg.plan);
      }
      await recomputeChatGPTSnapshot();
      return { kind: 'ACK' };
    }

    if (msg.kind === 'REFRESH_REQUESTED') {
      const [claudeBackoff, mjBackoff, elBackoff, grokBackoff, pxBackoff, leoBackoff] =
        await Promise.all([
          getBackoff(),
          getMidjourneyBackoff(),
          getElevenLabsBackoff(),
          getGrokBackoff(),
          getPerplexityBackoff(),
          getLeonardoBackoff(),
        ]);
      // Report the earliest active backoff expiry to the caller.
      const now = Date.now();
      const activeBackoffs = [claudeBackoff, mjBackoff, elBackoff, grokBackoff, pxBackoff, leoBackoff]
        .filter((b): b is NonNullable<typeof b> => b !== null && now < b.until)
        .map((b) => b.until);
      if (activeBackoffs.length === 6) {
        // All six pollable web providers are backed off — surface the soonest expiry.
        return { kind: 'REFRESH_BACKOFF', until: Math.min(...activeBackoffs) };
      }
      try {
        await Promise.all([
          pollClaude('manual'),
          pollMidjourney('manual'),
          pollElevenLabs('manual'),
          pollGrok('manual'),
          pollPerplexity('manual'),
          pollLeonardo('manual'),
          redetectChatGPTPlan('manual'),
        ]);
        await recomputeChatGPTSnapshot();
        // geminiConsumer is content-script-driven — no manual re-fetch here.
        // leonardo re-fetches from cached creds (skips silently if none yet).
        return { kind: 'REFRESH_COMPLETE' };
      } catch (err) {
        return { kind: 'REFRESH_FAILED', error: String(err) };
      }
    }

    return undefined;
  },
);

async function scheduleAlarms(): Promise<void> {
  await Promise.all([
    browser.alarms.create(CLAUDE_ALARM, { periodInMinutes: POLL_PERIOD_MIN }),
    browser.alarms.create(MIDJOURNEY_ALARM, { periodInMinutes: MIDJOURNEY_POLL_PERIOD_MIN }),
    browser.alarms.create(ELEVENLABS_ALARM, { periodInMinutes: ELEVENLABS_POLL_PERIOD_MIN }),
    browser.alarms.create(GROK_ALARM, { periodInMinutes: GROK_POLL_PERIOD_MIN }),
    browser.alarms.create(PERPLEXITY_ALARM, { periodInMinutes: PERPLEXITY_POLL_PERIOD_MIN }),
    browser.alarms.create(LEONARDO_ALARM, { periodInMinutes: LEONARDO_POLL_PERIOD_MIN }),
    browser.alarms.create(PLAN_REDETECT_ALARM, { periodInMinutes: PLAN_REDETECT_PERIOD_MIN }),
    browser.alarms.create(BRIDGE_HEARTBEAT_ALARM, { periodInMinutes: 1 }),
  ]);
}

// ── Claude poll ─────────────────────────────────────────────

export async function pollClaude(trigger: 'install' | 'alarm' | 'manual'): Promise<void> {
  const existing = await getBackoff();
  if (existing && Date.now() < existing.until && trigger !== 'manual') {
    console.log(`[tokenomics] skipping claude ${trigger} poll, backoff until`, new Date(existing.until));
    return;
  }

  try {
    const snapshot = await fetchClaudeUsage();
    await setClaudeSnapshot(snapshot);
    scheduleBridgeSend('snapshot');
    await setClaudeAuth('authenticated');
    await setBackoff(null);
    await updateBadge();
    console.log(`[tokenomics] claude poll ok (${trigger})`, snapshot);
  } catch (err) {
    if (err instanceof AuthError) {
      await setClaudeAuth('unauthenticated');
      await updateBadge();
      console.log('[tokenomics] claude not signed in');
    } else if (err instanceof RateLimitError) {
      const next = nextBackoff(existing);
      await setBackoff(next);
      console.warn('[tokenomics] claude rate limited until', new Date(next.until));
      throw err;
    } else {
      console.error('[tokenomics] claude poll failed', err);
      throw err;
    }
  }
}

function nextBackoff(prev: { nextDelayMs: number } | null) {
  const delay = prev?.nextDelayMs ?? BACKOFF_INITIAL_MS;
  return {
    until: Date.now() + delay,
    nextDelayMs: Math.min(delay * 2, BACKOFF_MAX_MS),
  };
}

// ── Midjourney poll ─────────────────────────────────────────

export async function pollMidjourney(trigger: 'install' | 'alarm' | 'manual'): Promise<void> {
  const existing = await getMidjourneyBackoff();
  if (existing && Date.now() < existing.until && trigger !== 'manual') {
    console.log(`[tokenomics] skipping midjourney ${trigger} poll, backoff until`, new Date(existing.until));
    return;
  }

  try {
    const snapshot = await fetchMidjourneyUsage();
    await setMidjourneySnapshot(snapshot);
    scheduleBridgeSend('snapshot');
    await setMidjourneyAuth('authenticated');
    await setMidjourneyBackoff(null);
    await updateBadge();
    console.log(`[tokenomics] midjourney poll ok (${trigger})`, snapshot);
  } catch (err) {
    if (err instanceof MJAuthError) {
      await setMidjourneyAuth('unauthenticated');
      await updateBadge();
      console.log('[tokenomics] midjourney not signed in');
    } else if (err instanceof MJRateLimitError) {
      const next = nextBackoff(existing);
      await setMidjourneyBackoff(next);
      console.warn('[tokenomics] midjourney rate limited until', new Date(next.until));
      throw err;
    } else {
      console.error('[tokenomics] midjourney poll failed', err);
      throw err;
    }
  }
}

// ── ElevenLabs poll ─────────────────────────────────────────

/**
 * Poll ElevenLabs subscription usage via Firebase Bearer token auth.
 *
 * The token is cached by the SW after the elevenlabs-grab content script
 * delivers it via ELEVENLABS_TOKEN message. If no token is cached yet, the
 * poll is skipped (the content script will deliver one when the user visits
 * elevenlabs.io).
 */
export async function pollElevenLabs(trigger: 'install' | 'alarm' | 'manual'): Promise<void> {
  const existing = await getElevenLabsBackoff();
  if (existing && Date.now() < existing.until && trigger !== 'manual') {
    console.log(`[tokenomics] skipping elevenlabs ${trigger} poll, backoff until`, new Date(existing.until));
    return;
  }

  const firebaseToken = await getElevenLabsFirebaseToken();
  if (!firebaseToken) {
    // No token yet — the content script hasn't run (user hasn't visited elevenlabs.io).
    console.log('[tokenomics] elevenlabs: no firebase token cached yet, skipping poll');
    return;
  }

  try {
    const snapshot = await fetchElevenLabsUsage(firebaseToken);
    await setElevenLabsSnapshot(snapshot);
    scheduleBridgeSend('snapshot');
    await setElevenLabsAuth('authenticated');
    await setElevenLabsBackoff(null);
    await updateBadge();
    console.log(`[tokenomics] elevenlabs poll ok (${trigger})`, snapshot);
  } catch (err) {
    if (err instanceof ELAuthError) {
      await setElevenLabsAuth('unauthenticated');
      await updateBadge();
      console.log('[tokenomics] elevenlabs not signed in');
    } else if (err instanceof ELRateLimitError) {
      const next = nextBackoff(existing);
      await setElevenLabsBackoff(next);
      console.warn('[tokenomics] elevenlabs rate limited until', new Date(next.until));
      throw err;
    } else {
      console.error('[tokenomics] elevenlabs poll failed', err);
      throw err;
    }
  }
}

// ── Grok poll ───────────────────────────────────────────────

export async function pollGrok(trigger: 'install' | 'alarm' | 'manual'): Promise<void> {
  const existing = await getGrokBackoff();
  if (existing && Date.now() < existing.until && trigger !== 'manual') {
    console.log(`[tokenomics] skipping grok ${trigger} poll, backoff until`, new Date(existing.until));
    return;
  }

  try {
    const snapshot = await fetchGrokUsage();
    await setGrokSnapshot(snapshot);
    scheduleBridgeSend('snapshot');
    await setGrokAuth('authenticated');
    await setGrokBackoff(null);
    await updateBadge();
    console.log(`[tokenomics] grok poll ok (${trigger})`, snapshot);
  } catch (err) {
    if (err instanceof GrokAuthError) {
      await setGrokAuth('unauthenticated');
      await updateBadge();
      console.log('[tokenomics] grok not signed in');
    } else if (err instanceof GrokRateLimitError) {
      const next = nextBackoff(existing);
      await setGrokBackoff(next);
      console.warn('[tokenomics] grok rate limited until', new Date(next.until));
      throw err;
    } else {
      console.error('[tokenomics] grok poll failed', err);
      throw err;
    }
  }
}

// ── Perplexity poll ─────────────────────────────────────────

export async function pollPerplexity(trigger: 'install' | 'alarm' | 'manual'): Promise<void> {
  const existing = await getPerplexityBackoff();
  if (existing && Date.now() < existing.until && trigger !== 'manual') {
    console.log(`[tokenomics] skipping perplexity ${trigger} poll, backoff until`, new Date(existing.until));
    return;
  }

  try {
    const priorCaps = await getPerplexityCaps();
    const { snapshot, caps } = await fetchPerplexityUsage(priorCaps);
    await setPerplexityCaps(caps);
    await setPerplexitySnapshot(snapshot);
    scheduleBridgeSend('snapshot');
    await setPerplexityAuth('authenticated');
    await setPerplexityBackoff(null);
    await updateBadge();
    console.log(`[tokenomics] perplexity poll ok (${trigger})`, snapshot);
  } catch (err) {
    if (err instanceof PxAuthError) {
      await setPerplexityAuth('unauthenticated');
      await updateBadge();
      console.log('[tokenomics] perplexity not signed in');
    } else if (err instanceof PxRateLimitError) {
      const next = nextBackoff(existing);
      await setPerplexityBackoff(next);
      console.warn('[tokenomics] perplexity rate limited until', new Date(next.until));
      throw err;
    } else {
      console.error('[tokenomics] perplexity poll failed', err);
      throw err;
    }
  }
}

// ── Leonardo poll ───────────────────────────────────────────

/**
 * Poll Leonardo token balance via Cognito Bearer token + GraphQL.
 *
 * The token is cached by the SW after the leonardo-grab content script
 * delivers it via LEONARDO_TOKEN message. If no credentials are cached yet,
 * the poll is skipped.
 */
export async function pollLeonardo(trigger: 'install' | 'alarm' | 'manual'): Promise<void> {
  const existing = await getLeonardoBackoff();
  if (existing && Date.now() < existing.until && trigger !== 'manual') {
    console.log(`[tokenomics] skipping leonardo ${trigger} poll, backoff until`, new Date(existing.until));
    return;
  }

  const creds = await getLeonardoCredentials();
  if (!creds) {
    // No credentials yet — the content script hasn't run (user hasn't visited app.leonardo.ai).
    console.log('[tokenomics] leonardo: no cognito credentials cached yet, skipping poll');
    return;
  }

  try {
    const snapshot = await fetchLeonardoUsage(creds.idToken, creds.userSub);
    await setLeonardoSnapshot(snapshot);
    scheduleBridgeSend('snapshot');
    await setLeonardoAuth('authenticated');
    await setLeonardoBackoff(null);
    await updateBadge();
    console.log(`[tokenomics] leonardo poll ok (${trigger})`, snapshot);
  } catch (err) {
    if (err instanceof LeoAuthError) {
      await setLeonardoAuth('unauthenticated');
      await updateBadge();
      console.log('[tokenomics] leonardo not signed in');
    } else if (err instanceof LeoRateLimitError) {
      const next = nextBackoff(existing);
      await setLeonardoBackoff(next);
      console.warn('[tokenomics] leonardo rate limited until', new Date(next.until));
      throw err;
    } else {
      console.error('[tokenomics] leonardo poll failed', err);
      throw err;
    }
  }
}

// ── ChatGPT counter ─────────────────────────────────────────

async function recordChatGPTMessage(model: string | null, ts: number): Promise<void> {
  const existing = await getChatGPTEvents();
  const event: ChatGPTMessageEvent = { ts, model };
  const next = pruneEvents([...existing, event], Date.now());
  await setChatGPTEvents(next);
  console.log(`[tokenomics] chatgpt message observed (model=${model ?? 'unknown'})`);
  await recomputeChatGPTSnapshot();
}

export async function recomputeChatGPTSnapshot(): Promise<void> {
  // Exact first: real usage from /wham/usage via the web session token.
  const exact = await fetchExactChatGPTSnapshot();
  if (exact) {
    await setChatGPTSnapshot(exact);
    scheduleBridgeSend('snapshot');
    await updateBadge();
    return;
  }

  // Fallback: local-counter estimate (token/endpoint unavailable).
  const [events, plan] = await Promise.all([getChatGPTEvents(), getChatGPTPlanEffective()]);
  if (events.length === 0 && plan === 'unknown') {
    // Nothing observed yet and no plan known — leave the empty state alone.
    return;
  }
  const snapshot = deriveSnapshot(events, plan);
  await setChatGPTSnapshot(snapshot);
  scheduleBridgeSend('snapshot');
  await updateBadge();
}

async function redetectChatGPTPlan(trigger: 'install' | 'alarm' | 'manual'): Promise<void> {
  try {
    const plan = await detectChatGPTPlan();
    await setChatGPTPlanAuto(plan);
    console.log(`[tokenomics] chatgpt plan auto-detected as '${plan}' (${trigger})`);
    if (plan !== 'unknown') await recomputeChatGPTSnapshot();
  } catch (err) {
    console.warn('[tokenomics] chatgpt plan detect failed', err);
  }
}

// ── Toolbar badge ───────────────────────────────────────────

async function updateBadge(): Promise<void> {
  const [pinned, claude, chatgpt, midjourney, geminiConsumer, elevenlabs, grok, perplexity, leonardo] =
    await Promise.all([
      getPinnedProvider(),
      getClaudeSnapshot(),
      getChatGPTSnapshot(),
      getMidjourneySnapshot(),
      getGeminiConsumerSnapshot(),
      getElevenLabsSnapshot(),
      getGrokSnapshot(),
      getPerplexitySnapshot(),
      getLeonardoSnapshot(),
    ]);
  const live: Partial<Record<ProviderId, ProviderUsageSnapshot>> = {};
  if (claude) live.claude = claude;
  if (chatgpt) live.chatgpt = chatgpt;
  if (midjourney) live.midjourney = midjourney;
  if (geminiConsumer) live.geminiConsumer = geminiConsumer;
  if (elevenlabs) live.elevenlabs = elevenlabs;
  if (grok) live.grok = grok;
  if (perplexity) live.perplexity = perplexity;
  if (leonardo) live.leonardo = leonardo;

  let value: number | null = null;
  if (pinned && live[pinned]) {
    value = Math.round(live[pinned]!.shortWindow.utilization);
  } else if (!pinned) {
    const utils = Object.values(live).map((s) => Math.round(s!.shortWindow.utilization));
    if (utils.length > 0) value = Math.max(...utils);
  }

  if (value === null) {
    await clearBadge();
    return;
  }
  await browser.action.setBadgeText({ text: `${value}%` });
  await browser.action.setBadgeBackgroundColor({ color: '#2F84BF' });
  if ('setBadgeTextColor' in browser.action) {
    await browser.action.setBadgeTextColor({ color: '#FFFFFF' });
  }
}

async function clearBadge(): Promise<void> {
  await browser.action.setBadgeText({ text: '' });
}
