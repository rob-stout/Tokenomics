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

const SUBSCRIPTION_URL = 'https://api.us.elevenlabs.io/v1/user/subscription';
const THIRTY_DAY_SEC = 30 * 24 * 3600;

export class AuthError extends Error {
  constructor(status: number) {
    super(`Not signed in to elevenlabs.io (status ${status})`);
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
 * Fetch the subscription response using a Firebase Bearer token.
 *
 * The token is obtained by the elevenlabs-grab content script (IndexedDB read
 * on elevenlabs.io) and passed here after the SW caches it.
 *
 * @param firebaseToken - Firebase ID token from IndexedDB stsTokenManager.accessToken.
 */
async function fetchSubscription(firebaseToken: string): Promise<SubscriptionResponse> {
  const res = await fetch(SUBSCRIPTION_URL, {
    headers: { Authorization: `Bearer ${firebaseToken}` },
  });

  if (res.status === 401 || res.status === 403) throw new AuthError(res.status);
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`elevenlabs subscription fetch failed: ${res.status}`);

  const raw = (await res.json()) as SubscriptionResponse;
  console.log('[tokenomics] elevenlabs raw subscription response:', raw);
  return raw;
}

// ── Public API ────────────────────────────────────────────────

/**
 * Fetch ElevenLabs subscription usage using a Firebase Bearer token.
 *
 * @param firebaseToken - The access token from the elevenlabs-grab content script.
 */
export async function fetchElevenLabsUsage(firebaseToken: string): Promise<ProviderUsageSnapshot> {
  const raw = await fetchSubscription(firebaseToken);
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
  // A past or missing reset timestamp is not meaningful — fall back to now + 30d.
  // This prevents the UI from showing a negative or "resets now" countdown.
  const resetMs = resetSec > 0 ? resetSec * 1000 : 0;
  const resetsAt =
    resetMs > now
      ? new Date(resetMs).toISOString()
      : new Date(now + THIRTY_DAY_SEC * 1000).toISOString();

  const shortWindow: WindowUsage = {
    label: 'Characters',
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
