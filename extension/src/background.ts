import browser from 'webextension-polyfill';
import {
  deriveSnapshot,
  detectChatGPTPlan,
  pruneEvents,
  type ChatGPTMessageEvent,
} from './chatgpt';
import { AuthError, fetchClaudeUsage, RateLimitError } from './claude';
import { AuthError as MJAuthError, fetchMidjourneyUsage, RateLimitError as MJRateLimitError } from './midjourney';
import { AuthError as ELAuthError, fetchElevenLabsUsage, RateLimitError as ELRateLimitError } from './elevenlabs';
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
} from './storage';
import type { ProviderId } from './types';

const CLAUDE_ALARM = 'claude-poll';
const MIDJOURNEY_ALARM = 'midjourney-poll';
const ELEVENLABS_ALARM = 'elevenlabs-poll';
const PLAN_REDETECT_ALARM = 'chatgpt-plan-redetect';
const BRIDGE_HEARTBEAT_ALARM = 'bridgeHeartbeat';
const POLL_PERIOD_MIN = 5;
const MIDJOURNEY_POLL_PERIOD_MIN = 10; // less frequent — billing data changes slowly
const ELEVENLABS_POLL_PERIOD_MIN = 10; // monthly billing window, no need to poll rapidly
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
  void recomputeChatGPTSnapshot();
});

void sendBridgeBatch('ping').catch(() => undefined);

browser.runtime.onInstalled.addListener(async () => {
  await scheduleAlarms();
  void pollClaude('install');
  void pollMidjourney('install');
  void pollElevenLabs('install');
  void redetectChatGPTPlan('install');
});

browser.runtime.onStartup.addListener(async () => {
  await scheduleAlarms();
});

browser.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === CLAUDE_ALARM) void pollClaude('alarm');
  else if (alarm.name === MIDJOURNEY_ALARM) void pollMidjourney('alarm');
  else if (alarm.name === ELEVENLABS_ALARM) void pollElevenLabs('alarm');
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
      // Store it and bridge it to the Mac app immediately — no backoff
      // needed because the content script self-throttles at 5 min intervals.
      await setGeminiConsumerSnapshot(msg.snapshot);
      scheduleBridgeSend('snapshot');
      await updateBadge();
      console.log('[tokenomics] gemini consumer snapshot received', msg.snapshot);
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
      const [claudeBackoff, mjBackoff, elBackoff] = await Promise.all([
        getBackoff(),
        getMidjourneyBackoff(),
        getElevenLabsBackoff(),
      ]);
      // Report the earliest active backoff expiry to the caller.
      const now = Date.now();
      const activeBackoffs = [claudeBackoff, mjBackoff, elBackoff]
        .filter((b): b is NonNullable<typeof b> => b !== null && now < b.until)
        .map((b) => b.until);
      if (activeBackoffs.length === 3) {
        // All three providers are backed off — surface the soonest expiry.
        return { kind: 'REFRESH_BACKOFF', until: Math.min(...activeBackoffs) };
      }
      try {
        await Promise.all([
          pollClaude('manual'),
          pollMidjourney('manual'),
          pollElevenLabs('manual'),
          redetectChatGPTPlan('manual'),
        ]);
        await recomputeChatGPTSnapshot();
        // geminiConsumer is content-script-driven — no manual re-fetch available here;
        // the existing snapshot is already the freshest data we have.
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
 * Poll ElevenLabs subscription usage via cookie-auth (hypothesis — UNVERIFIED).
 * Mirrors the Midjourney poll structure: exponential backoff on 429,
 * auth-state tracking, bridge notification on success.
 */
export async function pollElevenLabs(trigger: 'install' | 'alarm' | 'manual'): Promise<void> {
  const existing = await getElevenLabsBackoff();
  if (existing && Date.now() < existing.until && trigger !== 'manual') {
    console.log(`[tokenomics] skipping elevenlabs ${trigger} poll, backoff until`, new Date(existing.until));
    return;
  }

  try {
    const snapshot = await fetchElevenLabsUsage();
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
  const [pinned, claude, chatgpt, midjourney, geminiConsumer, elevenlabs] = await Promise.all([
    getPinnedProvider(),
    getClaudeSnapshot(),
    getChatGPTSnapshot(),
    getMidjourneySnapshot(),
    getGeminiConsumerSnapshot(),
    getElevenLabsSnapshot(),
  ]);
  const live: Partial<Record<ProviderId, ProviderUsageSnapshot>> = {};
  if (claude) live.claude = claude;
  if (chatgpt) live.codex = chatgpt;
  if (midjourney) live.midjourney = midjourney;
  if (geminiConsumer) live.geminiConsumer = geminiConsumer;
  if (elevenlabs) live.elevenlabs = elevenlabs;

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
