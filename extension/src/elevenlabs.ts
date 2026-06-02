/**
 * ElevenLabs usage reader.
 *
 * Polls https://api.elevenlabs.io/v1/user/subscription from the service worker
 * using the browser session cookie (credentials: 'include'). This mirrors the
 * claude.ts pattern — no API key, no DOM scraping, no content script needed.
 *
 * ── AUTH HYPOTHESIS (UNVERIFIED) ──────────────────────────────────────────
 * The ElevenLabs public API requires an `xi-api-key` header. Whether the
 * *web session* authenticates this endpoint via a first-party cookie (so that
 * `credentials: 'include'` works from a service worker) is UNCONFIRMED as of
 * 2026-06-02. Cookie-auth is the hypothesis because:
 *   (a) elevenlabs.io and api.elevenlabs.io share the same registered domain,
 *       so first-party session cookies would be sent cross-subdomain.
 *   (b) This is exactly how claude.ai and midjourney.com work — both use
 *       cookie auth on their own API subdomains.
 *
 * On a successful poll, the raw response is logged so a 5-minute capture from
 * a logged-in tab can confirm the shape and the auth mechanism.
 *
 * On a 401/403, a loud console message names the fallback path — see the
 * FALLBACK PIVOT section below.
 * ──────────────────────────────────────────────────────────────────────────
 *
 * ── FALLBACK PIVOT (if cookie-auth does not work) ─────────────────────────
 * If elevenlabs.io stores its session token in the page's JS heap (a Clerk
 * __session cookie or a bearer token via `window.__CLERK_FRONTEND_API`) rather
 * than transmitting it as a cookie accessible to the service worker, the fix
 * is to extract the token from a MAIN-world content script and relay it here —
 * exactly the pattern in content/gemini-main.ts for Gemini's XSRF tokens.
 *
 * To pivot:
 *   1. Add a content script entry in manifest.json for `https://elevenlabs.io/*`
 *      with `world: "MAIN"`.
 *   2. In that script, read `window.__clerk_db_jwt` (or whatever Clerk exposes)
 *      and send `{ kind: 'ELEVENLABS_TOKEN', token }` to the SW via
 *      chrome.runtime.sendMessage.
 *   3. In background.ts, cache the token in storage (keyed
 *      `elevenLabsSessionToken`) and pass it to `fetchElevenLabsUsage()`.
 *   4. Replace `credentials: 'include'` here with
 *      `headers: { Authorization: \`Bearer ${token}\` }`.
 *
 * The `fetchSubscription()` function below is the only thing that needs
 * changing — `mapToSnapshot()` is pure and stays unchanged.
 * ──────────────────────────────────────────────────────────────────────────
 *
 * Billing unit: characters (not tokens, not credits).
 *   utilization% = character_count / character_limit * 100
 * Monthly window — `next_character_count_reset_unix` is an epoch-seconds field.
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

const SUBSCRIPTION_URL = 'https://api.elevenlabs.io/v1/user/subscription';
const THIRTY_DAY_SEC = 30 * 24 * 3600;

export class AuthError extends Error {
  constructor(status: number) {
    super(`Not signed in to elevenlabs.io (status ${status})`);
    this.name = 'AuthError';
  }
}

export class RateLimitError extends Error {
  constructor() {
    super('api.elevenlabs.io rate limited the request');
    this.name = 'RateLimitError';
  }
}

// ── Response shape (documented endpoint, fields we use) ──────

interface SubscriptionResponse {
  /** Characters consumed in the current billing period. */
  character_count?: number;
  /** Hard cap for the current plan. */
  character_limit?: number;
  /**
   * Epoch seconds when the character count resets.
   * Present on all paid and free plans.
   */
  next_character_count_reset_unix?: number;
  /**
   * Plan tier identifier — e.g. "free", "starter", "creator", "pro",
   * "scale", "business". Title-cased to derive planLabel.
   */
  tier?: string;
}

// ── Fetch layer (isolate for easy pivot to bearer-token auth) ─

/**
 * Fetch the subscription response from the ElevenLabs API.
 *
 * Uses `credentials: 'include'` (cookie-auth hypothesis). If this returns
 * a 401/403 the most likely cause is that elevenlabs.io does NOT forward a
 * session cookie to api.elevenlabs.io — see the FALLBACK PIVOT comment above.
 */
async function fetchSubscription(): Promise<SubscriptionResponse> {
  const res = await fetch(SUBSCRIPTION_URL, { credentials: 'include' });

  if (res.status === 401 || res.status === 403) {
    // Log loudly so a developer capture immediately surfaces the auth failure.
    console.log(
      `[tokenomics] elevenlabs auth failed (status ${res.status}) — web session may use a bearer token, not a cookie. See FALLBACK PIVOT comment in elevenlabs.ts.`,
    );
    throw new AuthError(res.status);
  }
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`elevenlabs subscription fetch failed: ${res.status}`);

  const raw = (await res.json()) as SubscriptionResponse;
  // Log the raw response so a 5-minute capture can verify the field names and
  // confirm that cookie-auth is working (or provide the bearer token shape for
  // the fallback pivot).
  console.log('[tokenomics] elevenlabs raw subscription response:', raw);
  return raw;
}

// ── Public API ────────────────────────────────────────────────

/**
 * Fetch ElevenLabs subscription usage using the web session cookie.
 *
 * NOTE: auth mechanism is cookie-auth hypothesis — UNVERIFIED as of 2026-06-02.
 * See the file-level comment for the fallback pivot path.
 */
export async function fetchElevenLabsUsage(): Promise<ProviderUsageSnapshot> {
  const raw = await fetchSubscription();
  return mapToSnapshot(raw, Date.now());
}

/**
 * Pure mapper from a SubscriptionResponse to a ProviderUsageSnapshot.
 * Exported for unit testing.
 *
 * @param raw  - The parsed JSON from /v1/user/subscription.
 * @param now  - Current time in milliseconds (injectable for tests).
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
  // If the field is missing (0 from num()), fall back to now + 30d — same
  // strategy as the Midjourney reader.
  const resetsAt =
    resetSec > 0
      ? new Date(resetSec * 1000).toISOString()
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
  // Known tiers from ElevenLabs docs — map to display-friendly names.
  switch (t) {
    case 'free':     return 'Free';
    case 'starter':  return 'Starter';
    case 'creator':  return 'Creator';
    case 'pro':      return 'Pro';
    case 'scale':    return 'Scale';
    case 'business': return 'Business';
    default:
      // Unknown future tier — capitalize first letter as a safe fallback.
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
