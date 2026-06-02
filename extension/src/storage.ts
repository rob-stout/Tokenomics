import browser from 'webextension-polyfill';
import type { ChatGPTMessageEvent, ChatGPTPlan } from './chatgpt';
import { isProviderId, type ProviderId } from './types';
import type { AuthState, BackoffState, ProviderUsageSnapshot } from './snapshot';

const KEYS = {
  selectedTab: 'selectedTab',
  pinnedProvider: 'pinnedProvider',
  claudeOrgId: 'claudeOrgId',
  claudeSnapshot: 'claudeSnapshot',
  claudeAuth: 'claudeAuth',
  claudeBackoff: 'claudeBackoff',
  chatgptSnapshot: 'chatgptSnapshot',
  chatgptEvents: 'chatgptEvents',
  chatgptPlanAuto: 'chatgptPlanAuto',
  chatgptPlanOverride: 'chatgptPlanOverride',
  midjourneySnapshot: 'midjourneySnapshot',
  midjourneyAuth: 'midjourneyAuth',
  midjourneyBackoff: 'midjourneyBackoff',
  geminiConsumerSnapshot: 'geminiConsumerSnapshot',
} as const;

const ORG_ID_TTL_MS = 24 * 60 * 60 * 1000;

interface CachedOrgId {
  value: string;
  expiresAt: number;
}

// ── selectedTab ─────────────────────────────────────────────

export async function getSelectedTab(): Promise<ProviderId | null> {
  const result = await browser.storage.local.get(KEYS.selectedTab);
  const raw = result[KEYS.selectedTab];
  return isProviderId(raw) ? raw : null;
}

export async function setSelectedTab(tab: ProviderId): Promise<void> {
  await browser.storage.local.set({ [KEYS.selectedTab]: tab });
}

// ── pinnedProvider ──────────────────────────────────────────

export async function getPinnedProvider(): Promise<ProviderId | null> {
  const result = await browser.storage.local.get(KEYS.pinnedProvider);
  const raw = result[KEYS.pinnedProvider];
  return isProviderId(raw) ? raw : null;
}

export async function setPinnedProvider(provider: ProviderId | null): Promise<void> {
  if (provider === null) {
    await browser.storage.local.remove(KEYS.pinnedProvider);
  } else {
    await browser.storage.local.set({ [KEYS.pinnedProvider]: provider });
  }
}

// ── Claude org id cache (24h TTL) ───────────────────────────

export async function getCachedOrgId(): Promise<string | null> {
  const result = await browser.storage.local.get(KEYS.claudeOrgId);
  const raw = result[KEYS.claudeOrgId] as CachedOrgId | undefined;
  if (!raw || typeof raw.value !== 'string') return null;
  if (Date.now() > raw.expiresAt) return null;
  return raw.value;
}

export async function setCachedOrgId(value: string): Promise<void> {
  const cached: CachedOrgId = { value, expiresAt: Date.now() + ORG_ID_TTL_MS };
  await browser.storage.local.set({ [KEYS.claudeOrgId]: cached });
}

// ── Claude snapshot ─────────────────────────────────────────

export async function getClaudeSnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.claudeSnapshot);
  const raw = result[KEYS.claudeSnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setClaudeSnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.claudeSnapshot]: snapshot });
}

// ── Claude auth state ───────────────────────────────────────

export async function getClaudeAuth(): Promise<AuthState> {
  const result = await browser.storage.local.get(KEYS.claudeAuth);
  const raw = result[KEYS.claudeAuth];
  if (raw === 'authenticated' || raw === 'unauthenticated') return raw;
  return 'unknown';
}

export async function setClaudeAuth(state: AuthState): Promise<void> {
  await browser.storage.local.set({ [KEYS.claudeAuth]: state });
}

// ── ChatGPT snapshot (derived from counter) ─────────────────

export async function getChatGPTSnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.chatgptSnapshot);
  const raw = result[KEYS.chatgptSnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setChatGPTSnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.chatgptSnapshot]: snapshot });
}

// ── ChatGPT counter (rolling log of message events) ─────────

export async function getChatGPTEvents(): Promise<ChatGPTMessageEvent[]> {
  const result = await browser.storage.local.get(KEYS.chatgptEvents);
  const raw = result[KEYS.chatgptEvents];
  if (!Array.isArray(raw)) return [];
  return raw as ChatGPTMessageEvent[];
}

export async function setChatGPTEvents(events: ChatGPTMessageEvent[]): Promise<void> {
  await browser.storage.local.set({ [KEYS.chatgptEvents]: events });
}

// ── ChatGPT plan (auto-detected + manual override) ──────────

export async function getChatGPTPlanAuto(): Promise<ChatGPTPlan> {
  const result = await browser.storage.local.get(KEYS.chatgptPlanAuto);
  const raw = result[KEYS.chatgptPlanAuto];
  return isChatGPTPlan(raw) ? raw : 'unknown';
}

export async function setChatGPTPlanAuto(plan: ChatGPTPlan): Promise<void> {
  await browser.storage.local.set({ [KEYS.chatgptPlanAuto]: plan });
}

export async function getChatGPTPlanOverride(): Promise<ChatGPTPlan | null> {
  const result = await browser.storage.local.get(KEYS.chatgptPlanOverride);
  const raw = result[KEYS.chatgptPlanOverride];
  return isChatGPTPlan(raw) && raw !== 'unknown' ? raw : null;
}

export async function setChatGPTPlanOverride(plan: ChatGPTPlan | null): Promise<void> {
  if (plan === null || plan === 'unknown') {
    await browser.storage.local.remove(KEYS.chatgptPlanOverride);
  } else {
    await browser.storage.local.set({ [KEYS.chatgptPlanOverride]: plan });
  }
}

/** Resolves the effective plan: manual override wins; otherwise auto. */
export async function getChatGPTPlanEffective(): Promise<ChatGPTPlan> {
  const [override, auto] = await Promise.all([
    getChatGPTPlanOverride(),
    getChatGPTPlanAuto(),
  ]);
  return override ?? auto;
}

function isChatGPTPlan(value: unknown): value is ChatGPTPlan {
  return value === 'free' || value === 'plus' || value === 'pro' || value === 'team' || value === 'unknown';
}

// ── Rate-limit backoff (generalised per-provider) ──────────

type BackoffKey = typeof KEYS.claudeBackoff | typeof KEYS.midjourneyBackoff;

async function getBackoffForKey(key: BackoffKey): Promise<BackoffState | null> {
  const result = await browser.storage.local.get(key);
  const raw = result[key];
  if (
    !raw ||
    typeof raw !== 'object' ||
    typeof (raw as BackoffState).until !== 'number' ||
    typeof (raw as BackoffState).nextDelayMs !== 'number'
  ) {
    return null;
  }
  return raw as BackoffState;
}

async function setBackoffForKey(key: BackoffKey, state: BackoffState | null): Promise<void> {
  if (state === null) {
    await browser.storage.local.remove(key);
  } else {
    await browser.storage.local.set({ [key]: state });
  }
}

/** Claude rate-limit backoff. */
export async function getBackoff(): Promise<BackoffState | null> {
  return getBackoffForKey(KEYS.claudeBackoff);
}

export async function setBackoff(state: BackoffState | null): Promise<void> {
  return setBackoffForKey(KEYS.claudeBackoff, state);
}

/** Midjourney rate-limit backoff. */
export async function getMidjourneyBackoff(): Promise<BackoffState | null> {
  return getBackoffForKey(KEYS.midjourneyBackoff);
}

export async function setMidjourneyBackoff(state: BackoffState | null): Promise<void> {
  return setBackoffForKey(KEYS.midjourneyBackoff, state);
}

// ── Midjourney snapshot ─────────────────────────────────────

export async function getMidjourneySnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.midjourneySnapshot);
  const raw = result[KEYS.midjourneySnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setMidjourneySnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.midjourneySnapshot]: snapshot });
}

// ── Midjourney auth state ───────────────────────────────────

export async function getMidjourneyAuth(): Promise<AuthState> {
  const result = await browser.storage.local.get(KEYS.midjourneyAuth);
  const raw = result[KEYS.midjourneyAuth];
  if (raw === 'authenticated' || raw === 'unauthenticated') return raw;
  return 'unknown';
}

export async function setMidjourneyAuth(state: AuthState): Promise<void> {
  await browser.storage.local.set({ [KEYS.midjourneyAuth]: state });
}

// ── Gemini consumer snapshot (web app, via content script) ──

export async function getGeminiConsumerSnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.geminiConsumerSnapshot);
  const raw = result[KEYS.geminiConsumerSnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setGeminiConsumerSnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.geminiConsumerSnapshot]: snapshot });
}
