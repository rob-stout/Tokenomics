import browser from 'webextension-polyfill';
import type { ChatGPTMessageEvent, ChatGPTPlan } from './chatgpt';
import type { PerplexityCaps } from './perplexity';
import { isProviderId, type ProviderId } from './types';
import type { AuthState, BackoffState, ProviderUsageSnapshot } from './snapshot';
import type { RenewalState } from './renewal';

const KEYS = {
  selectedTab: 'selectedTab',
  consent: 'consent',
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
  elevenLabsSnapshot: 'elevenLabsSnapshot',
  elevenLabsAuth: 'elevenLabsAuth',
  elevenLabsBackoff: 'elevenLabsBackoff',
  // ElevenLabs Firebase token (from elevenlabs-grab content script)
  elevenLabsFirebaseToken: 'elevenLabsFirebaseToken',
  // Grok
  grokSnapshot: 'grokSnapshot',
  grokAuth: 'grokAuth',
  grokBackoff: 'grokBackoff',
  // Perplexity
  perplexitySnapshot: 'perplexitySnapshot',
  perplexityAuth: 'perplexityAuth',
  perplexityBackoff: 'perplexityBackoff',
  // Perplexity inferred per-quota caps (high-water-mark — the endpoint returns
  // remaining-only with no totals and no plan field, so the cap is the max
  // remaining ever observed).
  perplexityCaps: 'perplexityCaps',
  // Leonardo
  leonardoSnapshot: 'leonardoSnapshot',
  leonardoAuth: 'leonardoAuth',
  leonardoBackoff: 'leonardoBackoff',
  // Leonardo Cognito credentials (from leonardo-grab content script)
  leonardoIdToken: 'leonardoIdToken',
  leonardoUserSub: 'leonardoUserSub',
  // User-pasted API keys (optional). When set, the matching reader uses the
  // vendor's official endpoint and the captured site token is deleted.
  // Never read by bridge.ts — keys stay in the browser.
  elevenLabsApiKey: 'elevenLabsApiKey',
  leonardoApiKey: 'leonardoApiKey',
  leonardoRenewal: 'leonardoRenewal',
  sunoRenewal: 'sunoRenewal',
  // Suno (snapshot only — fetched in-page by suno-watch; no token is ever stored)
  sunoSnapshot: 'sunoSnapshot',
  // Udio (cookie-auth SW poll, like Grok)
  udioSnapshot: 'udioSnapshot',
  udioAuth: 'udioAuth',
  udioBackoff: 'udioBackoff',
  // UI preference: show site names instead of vendor logos
  showSiteNames: 'showSiteNames',
} as const;

const ORG_ID_TTL_MS = 24 * 60 * 60 * 1000;

interface CachedOrgId {
  value: string;
  expiresAt: number;
}

// ── selectedTab ─────────────────────────────────────────────

// ── Consent ────────────────────────────────────────────────────────
//
// Chrome Web Store User Data policy (Aug 2026): nothing may be read until the
// user agrees to an in-extension disclosure. Every reader checks this first.
// Bump CONSENT_VERSION whenever the disclosure's substance changes — users
// who agreed to an older version are asked again.

// v2: added Suno (in-page read of suno.com's session cookie), Udio, and
// user-pasted API keys for ElevenLabs / Leonardo. Neither shipped before v2.
export const CONSENT_VERSION = 2;

export async function hasConsent(): Promise<boolean> {
  const result = await browser.storage.local.get(KEYS.consent);
  const raw = result[KEYS.consent] as { version?: unknown } | undefined;
  return typeof raw?.version === 'number' && raw.version >= CONSENT_VERSION;
}

export async function grantConsent(): Promise<void> {
  await browser.storage.local.set({
    [KEYS.consent]: { version: CONSENT_VERSION, grantedAt: Date.now() },
  });
}

/** Withdraws consent and deletes everything the extension has stored. */
export async function revokeConsentAndClear(): Promise<void> {
  await browser.storage.local.clear();
}

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

// ── ElevenLabs Firebase token (from content script) ─────────

export async function getElevenLabsFirebaseToken(): Promise<string | null> {
  const result = await browser.storage.local.get(KEYS.elevenLabsFirebaseToken);
  const raw = result[KEYS.elevenLabsFirebaseToken];
  return typeof raw === 'string' && raw.length > 0 ? raw : null;
}

export async function setElevenLabsFirebaseToken(token: string): Promise<void> {
  await browser.storage.local.set({ [KEYS.elevenLabsFirebaseToken]: token });
}

// ── Grok snapshot ───────────────────────────────────────────

export async function getGrokSnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.grokSnapshot);
  const raw = result[KEYS.grokSnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setGrokSnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.grokSnapshot]: snapshot });
}

// ── Grok auth state ─────────────────────────────────────────

export async function getGrokAuth(): Promise<AuthState> {
  const result = await browser.storage.local.get(KEYS.grokAuth);
  const raw = result[KEYS.grokAuth];
  if (raw === 'authenticated' || raw === 'unauthenticated') return raw;
  return 'unknown';
}

export async function setGrokAuth(state: AuthState): Promise<void> {
  await browser.storage.local.set({ [KEYS.grokAuth]: state });
}

// ── Perplexity snapshot ─────────────────────────────────────

export async function getPerplexitySnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.perplexitySnapshot);
  const raw = result[KEYS.perplexitySnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setPerplexitySnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.perplexitySnapshot]: snapshot });
}

// ── Perplexity auth state ───────────────────────────────────

export async function getPerplexityAuth(): Promise<AuthState> {
  const result = await browser.storage.local.get(KEYS.perplexityAuth);
  const raw = result[KEYS.perplexityAuth];
  if (raw === 'authenticated' || raw === 'unauthenticated') return raw;
  return 'unknown';
}

export async function setPerplexityAuth(state: AuthState): Promise<void> {
  await browser.storage.local.set({ [KEYS.perplexityAuth]: state });
}

// ── Perplexity inferred caps (high-water-mark) ──────────────

export async function getPerplexityCaps(): Promise<PerplexityCaps> {
  const result = await browser.storage.local.get(KEYS.perplexityCaps);
  const raw = result[KEYS.perplexityCaps];
  if (!raw || typeof raw !== 'object') return {};
  const caps = raw as PerplexityCaps;
  // Only surface finite, non-negative numbers; ignore anything else.
  const out: PerplexityCaps = {};
  if (typeof caps.pro === 'number' && caps.pro >= 0) out.pro = caps.pro;
  if (typeof caps.research === 'number' && caps.research >= 0) out.research = caps.research;
  if (typeof caps.labs === 'number' && caps.labs >= 0) out.labs = caps.labs;
  return out;
}

export async function setPerplexityCaps(caps: PerplexityCaps): Promise<void> {
  await browser.storage.local.set({ [KEYS.perplexityCaps]: caps });
}

// ── Leonardo snapshot ───────────────────────────────────────

export async function getLeonardoSnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.leonardoSnapshot);
  const raw = result[KEYS.leonardoSnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setLeonardoSnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.leonardoSnapshot]: snapshot });
}

// ── Renewal tracking (learned cycle day; see renewal.ts) ────

export type RenewalProvider = 'leonardo' | 'suno';

const RENEWAL_KEY: Record<RenewalProvider, string> = {
  leonardo: KEYS.leonardoRenewal,
  suno: KEYS.sunoRenewal,
};

export async function getRenewal(provider: RenewalProvider): Promise<RenewalState | null> {
  const result = await browser.storage.local.get(RENEWAL_KEY[provider]);
  const raw = result[RENEWAL_KEY[provider]];
  if (!raw || typeof raw !== 'object') return null;
  return raw as RenewalState;
}

export async function setRenewal(provider: RenewalProvider, state: RenewalState): Promise<void> {
  await browser.storage.local.set({ [RENEWAL_KEY[provider]]: state });
}

// ── Leonardo auth state ─────────────────────────────────────

export async function getLeonardoAuth(): Promise<AuthState> {
  const result = await browser.storage.local.get(KEYS.leonardoAuth);
  const raw = result[KEYS.leonardoAuth];
  if (raw === 'authenticated' || raw === 'unauthenticated') return raw;
  return 'unknown';
}

export async function setLeonardoAuth(state: AuthState): Promise<void> {
  await browser.storage.local.set({ [KEYS.leonardoAuth]: state });
}

// ── Leonardo Cognito credentials (from content script) ──────

export async function getLeonardoCredentials(): Promise<{ idToken: string; userSub: string } | null> {
  const result = await browser.storage.local.get([KEYS.leonardoIdToken, KEYS.leonardoUserSub]);
  const idToken = result[KEYS.leonardoIdToken];
  const userSub = result[KEYS.leonardoUserSub];
  if (typeof idToken !== 'string' || typeof userSub !== 'string') return null;
  if (idToken.length === 0 || userSub.length === 0) return null;
  return { idToken, userSub };
}

export async function setLeonardoCredentials(idToken: string, userSub: string): Promise<void> {
  await browser.storage.local.set({
    [KEYS.leonardoIdToken]: idToken,
    [KEYS.leonardoUserSub]: userSub,
  });
}

// ── User-pasted API keys (ElevenLabs, Leonardo) ─────────────
//
// Saving a key also deletes the site token captured earlier, so the extension
// holds one credential per site, not both. Removing a key just drops it; the
// capture path resumes the next time the user visits the site.

export type ApiKeyProvider = 'elevenlabs' | 'leonardo';

const API_KEY_STORAGE: Record<ApiKeyProvider, string> = {
  elevenlabs: KEYS.elevenLabsApiKey,
  leonardo: KEYS.leonardoApiKey,
};

const CAPTURED_TOKEN_STORAGE: Record<ApiKeyProvider, string[]> = {
  elevenlabs: [KEYS.elevenLabsFirebaseToken],
  leonardo: [KEYS.leonardoIdToken, KEYS.leonardoUserSub],
};

/** Snapshot + auth + backoff keys, cleared whenever the credential source changes. */
const READER_STATE_STORAGE: Record<ApiKeyProvider, string[]> = {
  elevenlabs: [KEYS.elevenLabsSnapshot, KEYS.elevenLabsAuth, KEYS.elevenLabsBackoff],
  leonardo: [KEYS.leonardoSnapshot, KEYS.leonardoAuth, KEYS.leonardoBackoff],
};

export async function getApiKey(provider: ApiKeyProvider): Promise<string | null> {
  const storageKey = API_KEY_STORAGE[provider];
  const result = await browser.storage.local.get(storageKey);
  const raw = result[storageKey];
  return typeof raw === 'string' && raw.length > 0 ? raw : null;
}

export async function setApiKey(provider: ApiKeyProvider, key: string): Promise<void> {
  await browser.storage.local.set({ [API_KEY_STORAGE[provider]]: key });
  await browser.storage.local.remove(CAPTURED_TOKEN_STORAGE[provider]);
}

/** Removes the key and the data read with it; the capture fallback takes over. */
export async function removeApiKey(provider: ApiKeyProvider): Promise<void> {
  await browser.storage.local.remove([
    API_KEY_STORAGE[provider],
    ...READER_STATE_STORAGE[provider],
  ]);
}

// ── Label mode (site names vs logos) ────────────────────────

/** null = the user never chose; callers fall back to the build default. */
export async function getShowSiteNames(): Promise<boolean | null> {
  const result = await browser.storage.local.get(KEYS.showSiteNames);
  const raw = result[KEYS.showSiteNames];
  return typeof raw === 'boolean' ? raw : null;
}

export async function setShowSiteNames(value: boolean): Promise<void> {
  await browser.storage.local.set({ [KEYS.showSiteNames]: value });
}

// ── Suno snapshot ───────────────────────────────────────────

export async function getSunoSnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.sunoSnapshot);
  const raw = result[KEYS.sunoSnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setSunoSnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.sunoSnapshot]: snapshot });
}

// ── Udio snapshot ───────────────────────────────────────────

export async function getUdioSnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.udioSnapshot);
  const raw = result[KEYS.udioSnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setUdioSnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.udioSnapshot]: snapshot });
}

// ── Udio auth state ─────────────────────────────────────────

export async function getUdioAuth(): Promise<AuthState> {
  const result = await browser.storage.local.get(KEYS.udioAuth);
  const raw = result[KEYS.udioAuth];
  return raw === 'authenticated' || raw === 'unauthenticated' ? raw : 'unknown';
}

export async function setUdioAuth(state: AuthState): Promise<void> {
  await browser.storage.local.set({ [KEYS.udioAuth]: state });
}

// ── Rate-limit backoff (generalised per-provider) ──────────

type BackoffKey =
  | typeof KEYS.claudeBackoff
  | typeof KEYS.midjourneyBackoff
  | typeof KEYS.elevenLabsBackoff
  | typeof KEYS.grokBackoff
  | typeof KEYS.perplexityBackoff
  | typeof KEYS.leonardoBackoff
  | typeof KEYS.udioBackoff;

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

// ── ElevenLabs snapshot ─────────────────────────────────────

export async function getElevenLabsSnapshot(): Promise<ProviderUsageSnapshot | null> {
  const result = await browser.storage.local.get(KEYS.elevenLabsSnapshot);
  const raw = result[KEYS.elevenLabsSnapshot];
  if (!raw || typeof raw !== 'object') return null;
  return raw as ProviderUsageSnapshot;
}

export async function setElevenLabsSnapshot(snapshot: ProviderUsageSnapshot): Promise<void> {
  await browser.storage.local.set({ [KEYS.elevenLabsSnapshot]: snapshot });
}

// ── ElevenLabs auth state ───────────────────────────────────

export async function getElevenLabsAuth(): Promise<AuthState> {
  const result = await browser.storage.local.get(KEYS.elevenLabsAuth);
  const raw = result[KEYS.elevenLabsAuth];
  if (raw === 'authenticated' || raw === 'unauthenticated') return raw;
  return 'unknown';
}

export async function setElevenLabsAuth(state: AuthState): Promise<void> {
  await browser.storage.local.set({ [KEYS.elevenLabsAuth]: state });
}

// ── ElevenLabs rate-limit backoff ───────────────────────────

export async function getElevenLabsBackoff(): Promise<BackoffState | null> {
  return getBackoffForKey(KEYS.elevenLabsBackoff);
}

export async function setElevenLabsBackoff(state: BackoffState | null): Promise<void> {
  return setBackoffForKey(KEYS.elevenLabsBackoff, state);
}

// ── Grok rate-limit backoff ─────────────────────────────────

export async function getGrokBackoff(): Promise<BackoffState | null> {
  return getBackoffForKey(KEYS.grokBackoff);
}

export async function setGrokBackoff(state: BackoffState | null): Promise<void> {
  return setBackoffForKey(KEYS.grokBackoff, state);
}

// ── Perplexity rate-limit backoff ───────────────────────────

export async function getPerplexityBackoff(): Promise<BackoffState | null> {
  return getBackoffForKey(KEYS.perplexityBackoff);
}

export async function setPerplexityBackoff(state: BackoffState | null): Promise<void> {
  return setBackoffForKey(KEYS.perplexityBackoff, state);
}

// ── Leonardo rate-limit backoff ─────────────────────────────

export async function getLeonardoBackoff(): Promise<BackoffState | null> {
  return getBackoffForKey(KEYS.leonardoBackoff);
}

export async function setLeonardoBackoff(state: BackoffState | null): Promise<void> {
  return setBackoffForKey(KEYS.leonardoBackoff, state);
}

// ── Udio rate-limit backoff ─────────────────────────────────

export async function getUdioBackoff(): Promise<BackoffState | null> {
  return getBackoffForKey(KEYS.udioBackoff);
}

export async function setUdioBackoff(state: BackoffState | null): Promise<void> {
  return setBackoffForKey(KEYS.udioBackoff, state);
}
