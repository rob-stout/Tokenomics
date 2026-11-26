/**
 * ElevenLabs usage reader.
 *
 * Auth: Firebase ID token (Bearer) delivered by a content script.
 *
 * ── HOW THE TOKEN IS OBTAINED ────────────────────────────────────────────────
 * ElevenLabs uses Firebase Authentication. On the elevenlabs.io web app the
 * Firebase SDK stores the current user's access token (a short-lived JWT) in
 * IndexedDB: database `firebaseLocalStorageDb`, object store `firebaseLocalStorage`.
 * The entry whose `fbase_key` matches the Firebase app's auth key contains a
 * `value` object with `stsTokenManager.accessToken`.
 *
 * A dedicated ISOLATED-world content script (`content/elevenlabs-grab.ts`) reads
 * this token and posts it to the service worker via `{ kind: 'ELEVENLABS_TOKEN' }`.
 * The SW caches the token and uses it for all subsequent API calls.
 *
 * ── API KEY (optional, preferred) ────────────────────────────────────────────
 * The user may paste an ElevenLabs API key in settings (needs the "User: read"
 * permission). Same endpoint, sent as `xi-api-key` and NO Authorization header.
 * Same response shape. When a key is stored the captured token is deleted.
 *
 * ── API HOST ─────────────────────────────────────────────────────────────────
 * The regional endpoint `api.us.elevenlabs.io` is used (confirmed live 2026-06-01).
 * `api.elevenlabs.io` (global) would work as a fallback but the token is only
 * valid for the region the account was created in.
 *
 * ── RESPONSE SHAPE ───────────────────────────────────────────────────────────
 * Real response (free account, 2026-06-01):
 *   { "tier": "free", "character_count": 0, "character_limit": 10000,
 *     "next_character_count_reset_unix": 1777606325, "status": "free" }
 *
 * Billing unit: characters (not tokens, not credits).
 *   utilization% = character_count / character_limit * 100
 * Monthly window — `next_character_count_reset_unix` is epoch seconds.
 * A past reset timestamp is treated as now + 30d (avoids a negative countdown).
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';
import { nextMonthlyReset } from './snapshot';

const SUBSCRIPTION_URL = 'https://api.us.elevenlabs.io/v1/user/subscription';
const THIRTY_DAY_SEC = 30 * 24 * 3600;

export type ElevenLabsCredential =
  | { kind: 'bearer'; token: string }
  | { kind: 'apiKey'; key: string };

export class AuthError extends Error {
  constructor(status: number, viaApiKey = false) {
    super(
      viaApiKey
        ? `ElevenLabs rejected the API key (status ${status}). Check it is correct and has the "User: read" permission. Keys from other data-residency regions may not work.`
        : `Not signed in to elevenlabs.io (status ${status})`,
    );
    this.name = 'AuthError';
  }
}

export class RateLimitError extends Error {
  constructor() {
    super('api.us.elevenlabs.io rate limited the request');
    this.name = 'RateLimitError';
  }
}

// ── Response shape (confirmed against live API 2026-06-01) ───

interface SubscriptionResponse {
  /** Characters consumed in the current billing period. */
  character_count?: number;
  /** Hard cap for the current plan. */
  character_limit?: number;
  /**
   * Epoch seconds when the character count resets.
   * A past value means the window has already reset; fall back to now + 30d.
   */
  next_character_count_reset_unix?: number;
  /**
   * Plan tier identifier — e.g. "free", "starter", "creator", "pro",
   * "scale", "business". Title-cased to derive planLabel.
   */
  tier?: string;
}

// ── Fetch layer ───────────────────────────────────────────────

/**
 * Exactly one auth header per credential: the API rejects requests that carry
 * both `xi-api-key` and `Authorization`.
 */
export function authHeaders(credential: ElevenLabsCredential): Record<string, string> {
  return credential.kind === 'apiKey'
    ? { 'xi-api-key': credential.key }
    : { Authorization: `Bearer ${credential.token}` };
}

/**
 * Fetch the subscription response using a Firebase Bearer token or API key.
 *
 * The token is obtained by the elevenlabs-grab content script (IndexedDB read
 * on elevenlabs.io) and passed here after the SW caches it.
 *
 * @param credential - Firebase ID token (captured) or the user's pasted API key.
 */
async function fetchSubscription(credential: ElevenLabsCredential): Promise<SubscriptionResponse> {
  const res = await fetch(SUBSCRIPTION_URL, { headers: authHeaders(credential) });

  if (res.status === 401 || res.status === 403) {
    throw new AuthError(res.status, credential.kind === 'apiKey');
  }
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`elevenlabs subscription fetch failed: ${res.status}`);

  const raw = (await res.json()) as SubscriptionResponse;
  console.log('[tokenomics] elevenlabs raw subscription response:', raw);
  return raw;
}

// ── Public API ────────────────────────────────────────────────

/**
 * Fetch ElevenLabs subscription usage. An API key (`xi-api-key`, official
 * endpoint) is preferred by the caller over the captured Firebase token.
 *
 * @param credential - API key, or the access token from the elevenlabs-grab content script.
 */
export async function fetchElevenLabsUsage(
  credential: ElevenLabsCredential,
): Promise<ProviderUsageSnapshot> {
  const raw = await fetchSubscription(credential);
  return mapToSnapshot(raw, Date.now());
}

/**
 * Pure mapper from a SubscriptionResponse to a ProviderUsageSnapshot.
 * Exported for unit testing.
 *
 * @param raw - The parsed JSON from /v1/user/subscription.
 * @param now - Current time in milliseconds (injectable for tests).
 */
export function mapToSnapshot(
  raw: SubscriptionResponse,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  const used = num(raw.character_count);
  const limit = num(raw.character_limit);

  // Avoid divide-by-zero on free/trial plans that report limit === 0.
  const utilization =
    limit > 0 ? Math.min(100, Math.max(0, Math.round((used / limit) * 100))) : 0;

  const resetSec = num(raw.next_character_count_reset_unix);
  const resetsAt = nextMonthlyReset(resetSec > 0 ? resetSec * 1000 : 0, now);

  const shortWindow: WindowUsage = {
    // ElevenLabs renamed characters to credits; the value is unchanged.
    label: 'Credits',
    utilization,
    resetsAt,
    windowDurationSec: THIRTY_DAY_SEC,
  };

  return {
    provider: 'elevenlabs',
    shortWindow,
    longWindow: null,
    extras: {},
    planLabel: tierToLabel(raw.tier),
    capturedAt: now,
    estimated: false,
  };
}

// ── Helpers ───────────────────────────────────────────────────

/**
 * Convert a tier string from the API to a user-facing plan label.
 * The API returns lowercase slugs; we Title-Case them for display.
 */
function tierToLabel(tier: string | undefined): string {
  if (!tier || typeof tier !== 'string' || tier.trim() === '') return 'ElevenLabs';
  const t = tier.trim().toLowerCase();
  switch (t) {
    case 'free':     return 'Free';
    case 'starter':  return 'Starter';
    case 'creator':  return 'Creator';
    case 'pro':      return 'Pro';
    case 'scale':    return 'Scale';
    case 'business': return 'Business';
    default:
      return t.charAt(0).toUpperCase() + t.slice(1);
  }
}

/** Safely coerce an unknown value to a finite number; returns 0 otherwise. */
function num(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const parsed = parseFloat(v);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}

export { nextMonthlyReset };
