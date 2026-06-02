/**
 * Grok usage reader.
 *
 * Polls https://grok.com/rest/rate-limits from the service worker via a POST
 * with `credentials: 'include'` (cookie auth). Confirmed working without any
 * anti-bot headers — session cookies from a logged-in grok.com tab are sent
 * automatically by the browser.
 *
 * Billing unit: fast queries per rolling 24-hour window.
 *   utilization% = (totalQueries - remainingQueries) / totalQueries * 100
 *
 * Real response (2026-06-01):
 *   { "windowSizeSeconds": 86400, "remainingQueries": 20, "totalQueries": 20,
 *     "lowEffortRateLimits": null, "highEffortRateLimits": null }
 *
 * The window is rolling — there is no absolute reset timestamp. We approximate
 * resetsAt as now + windowSizeSeconds, which gives the UI a sensible countdown.
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

const RATE_LIMITS_URL = 'https://grok.com/rest/rate-limits';
const DEFAULT_WINDOW_SEC = 86400; // 24h rolling window

export class AuthError extends Error {
  constructor(status: number) {
    super(`Not signed in to grok.com (status ${status})`);
    this.name = 'AuthError';
  }
}

export class RateLimitError extends Error {
  constructor() {
    super('grok.com rate limited the request');
    this.name = 'RateLimitError';
  }
}

// ── Response shape (confirmed against live API 2026-06-01) ───

interface RateLimitsResponse {
  windowSizeSeconds?: number;
  remainingQueries?: number;
  totalQueries?: number;
  // lowEffortRateLimits / highEffortRateLimits present but null on Free — ignored.
}

// ── Fetch layer ───────────────────────────────────────────────

async function fetchRateLimits(): Promise<RateLimitsResponse> {
  const res = await fetch(RATE_LIMITS_URL, {
    method: 'POST',
    credentials: 'include',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ modelName: 'fast' }),
  });

  if (res.status === 401 || res.status === 403) throw new AuthError(res.status);
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`grok rate-limits fetch failed: ${res.status}`);

  return (await res.json()) as RateLimitsResponse;
}

// ── Public API ────────────────────────────────────────────────

/**
 * Fetch Grok fast-query usage using the web session cookie.
 */
export async function fetchGrokUsage(): Promise<ProviderUsageSnapshot> {
  const raw = await fetchRateLimits();
  return mapToSnapshot(raw, Date.now());
}

/**
 * Pure mapper from a RateLimitsResponse to a ProviderUsageSnapshot.
 * Exported for unit testing.
 *
 * @param raw - The parsed JSON from /rest/rate-limits.
 * @param now - Current time in milliseconds (injectable for tests).
 */
export function mapToSnapshot(
  raw: RateLimitsResponse,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  const total = num(raw.totalQueries);
  const remaining = num(raw.remainingQueries);
  const windowSec = num(raw.windowSizeSeconds) || DEFAULT_WINDOW_SEC;

  // Avoid divide-by-zero when totalQueries is 0 (no plan / unexpected response).
  const used = Math.max(0, total - remaining);
  const utilization =
    total > 0 ? Math.min(100, Math.max(0, Math.round((used / total) * 100))) : 0;

  // Rolling window — no absolute reset timestamp from the API.
  // Approximate as now + windowSizeSeconds so the UI shows a sensible countdown.
  const resetsAt = new Date(now + windowSec * 1000).toISOString();

  const shortWindow: WindowUsage = {
    label: 'Fast Queries',
    utilization,
    resetsAt,
    windowDurationSec: windowSec,
    sublabelOverride: `${remaining} of ${total} left`,
  };

  return {
    provider: 'grok',
    shortWindow,
    longWindow: null,
    extras: {},
    planLabel: 'Grok',
    capturedAt: now,
    estimated: false,
  };
}

// ── Helpers ───────────────────────────────────────────────────

/** Safely coerce an unknown value to a finite number; returns 0 otherwise. */
function num(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const parsed = parseFloat(v);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}
