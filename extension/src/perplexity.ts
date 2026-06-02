/**
 * Perplexity usage reader.
 *
 * Polls GET https://www.perplexity.ai/rest/rate-limit/all from the service
 * worker with `credentials: 'include'` (cookie auth).
 *
 * IMPORTANT: This endpoint returns REMAINING counts only — no totals.
 * There is no clean utilization% available. The ring is left at 0 with a
 * sublabel displaying the remaining count until Perplexity exposes plan caps.
 *
 * // TODO: plan→cap table for a real ring
 * Known plan caps (as of 2026-06):
 *   - Pro: 5 "Pro searches" / day? (unconfirmed — no official docs)
 * Until totals are confirmed, utilization stays at 0.
 *
 * Real response (free account, 2026-06-01):
 *   {
 *     "free_queries": { "available": true, "remaining_detail": { "kind": "not_provided" } },
 *     "remaining_agentic_research": 0,
 *     "remaining_labs": 0,
 *     "remaining_pro": 5,
 *     "remaining_research": 0,
 *     "model_specific_limits": {},
 *     "sources": { ... ignored ... }
 *   }
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

const RATE_LIMIT_URL = 'https://www.perplexity.ai/rest/rate-limit/all';
const DAY_SEC = 86400;

export class AuthError extends Error {
  constructor(status: number) {
    super(`Not signed in to perplexity.ai (status ${status})`);
    this.name = 'AuthError';
  }
}

export class RateLimitError extends Error {
  constructor() {
    super('perplexity.ai rate limited the request');
    this.name = 'RateLimitError';
  }
}

// ── Response shape (confirmed against live API 2026-06-01) ───

interface RateLimitAllResponse {
  remaining_pro?: number;
  remaining_research?: number;
  remaining_labs?: number;
  remaining_agentic_research?: number;
  // free_queries and model_specific_limits present but not used for display.
}

// ── Fetch layer ───────────────────────────────────────────────

async function fetchRateLimitAll(): Promise<RateLimitAllResponse> {
  const res = await fetch(RATE_LIMIT_URL, { credentials: 'include' });

  if (res.status === 401 || res.status === 403) throw new AuthError(res.status);
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`perplexity rate-limit fetch failed: ${res.status}`);

  return (await res.json()) as RateLimitAllResponse;
}

// ── Public API ────────────────────────────────────────────────

/**
 * Fetch Perplexity search-quota usage using the web session cookie.
 */
export async function fetchPerplexityUsage(): Promise<ProviderUsageSnapshot> {
  const raw = await fetchRateLimitAll();
  return mapToSnapshot(raw, Date.now());
}

/**
 * Pure mapper from a RateLimitAllResponse to a ProviderUsageSnapshot.
 * Exported for unit testing.
 *
 * @param raw - The parsed JSON from /rest/rate-limit/all.
 * @param now - Current time in milliseconds (injectable for tests).
 */
export function mapToSnapshot(
  raw: RateLimitAllResponse,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  const remainingPro = num(raw.remaining_pro);
  const remainingResearch = num(raw.remaining_research);
  const remainingLabs = num(raw.remaining_labs);

  // No total available — utilization is unknown. Leave ring empty rather than
  // fabricating a percentage.
  // TODO: plan→cap table for a real ring — e.g. Pro plan may have 5 pro searches/day.
  const shortWindow: WindowUsage = {
    label: 'Pro Searches',
    utilization: 0,
    resetsAt: new Date(now + DAY_SEC * 1000).toISOString(),
    windowDurationSec: DAY_SEC,
    sublabelOverride: `${remainingPro} Pro left`,
  };

  // Only include the Deep Research long window if there is a non-zero value or
  // we received an explicit field, so the UI doesn't show a second empty bar
  // when the account has no deep research quota at all.
  const longWindow: WindowUsage | null =
    typeof raw.remaining_research === 'number'
      ? {
          label: 'Deep Research',
          utilization: 0,
          resetsAt: new Date(now + DAY_SEC * 1000).toISOString(),
          windowDurationSec: DAY_SEC,
          sublabelOverride: `${remainingResearch} left`,
        }
      : null;

  // Surface labs remaining in extras if present (non-zero or explicitly provided).
  const extras: ProviderUsageSnapshot['extras'] = {};
  if (typeof raw.remaining_labs === 'number' && remainingLabs > 0) {
    // Labs gets a synthetic window entry — no standard slot for it, so it will
    // only appear in providers that surface extras (e.g. a future Labs section).
    // For now it is captured but not displayed in the main UI.
    extras.labsRemaining = {
      label: 'Labs',
      utilization: 0,
      resetsAt: new Date(now + DAY_SEC * 1000).toISOString(),
      windowDurationSec: DAY_SEC,
      sublabelOverride: `${remainingLabs} left`,
    };
  }

  return {
    provider: 'perplexity',
    shortWindow,
    longWindow,
    extras,
    planLabel: 'Perplexity',
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
