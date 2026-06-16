/**
 * Perplexity usage reader.
 *
 * Polls GET https://www.perplexity.ai/rest/rate-limit/all from the service
 * worker with `credentials: 'include'` (cookie auth).
 *
 * ── WHY THERE IS NO PLAN→CAP TABLE (unlike Leonardo) ─────────────────────────
 * This endpoint returns REMAINING counts only — no totals — AND, critically, no
 * `plan`/`tier` field. So we cannot map a known plan to a fixed cap the way the
 * Leonardo reader does. Instead the cap is INFERRED as a high-water-mark: the
 * largest `remaining_*` value ever observed for each quota is treated as that
 * quota's cap (when the window is full, remaining == cap). Utilization is then
 * (cap - remaining) / cap.
 *
 * Caveat: until a full window has been observed at least once, the cap may be
 * under-calibrated (if the extension first sees the account mid-window). The
 * ring then under-reports usage until the next window reset bumps remaining back
 * to its true ceiling, at which point it self-corrects. It never over-reports.
 * The high-water-mark is persisted by the service worker (see storage.ts) and
 * passed into `mapToSnapshot`; `mergeCaps` computes the updated caps each poll.
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

/**
 * Inferred per-quota caps (high-water-mark). Each field is the largest
 * `remaining_*` value ever observed for that quota — used as the denominator
 * for the utilization ring. Persisted across polls by the service worker.
 */
export interface PerplexityCaps {
  pro?: number;
  research?: number;
  labs?: number;
}

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
 *
 * @param priorCaps - The previously persisted high-water-mark caps. Returns the
 *                    updated caps alongside the snapshot so the service worker
 *                    can persist them for the next poll.
 */
export async function fetchPerplexityUsage(
  priorCaps: PerplexityCaps = {},
): Promise<{ snapshot: ProviderUsageSnapshot; caps: PerplexityCaps }> {
  const raw = await fetchRateLimitAll();
  const caps = mergeCaps(raw, priorCaps);
  const snapshot = mapToSnapshot(raw, caps, Date.now());
  return { snapshot, caps };
}

/**
 * Fold this response's remaining counts into the high-water-mark caps.
 * Pure; exported for unit testing. Only fields present in the response are
 * updated, so a temporarily-missing field never resets a known cap.
 */
export function mergeCaps(
  raw: RateLimitAllResponse,
  prior: PerplexityCaps = {},
): PerplexityCaps {
  const next: PerplexityCaps = { ...prior };
  if (typeof raw.remaining_pro === 'number') {
    next.pro = Math.max(prior.pro ?? 0, raw.remaining_pro);
  }
  if (typeof raw.remaining_research === 'number') {
    next.research = Math.max(prior.research ?? 0, raw.remaining_research);
  }
  if (typeof raw.remaining_labs === 'number') {
    next.labs = Math.max(prior.labs ?? 0, raw.remaining_labs);
  }
  return next;
}

/**
 * Pure mapper from a RateLimitAllResponse to a ProviderUsageSnapshot.
 * Exported for unit testing.
 *
 * @param raw  - The parsed JSON from /rest/rate-limit/all.
 * @param caps - High-water-mark caps used as the utilization denominator. When a
 *               cap is unknown (0 / absent), the ring stays at 0 and the sublabel
 *               falls back to a remaining-only "X left" form.
 * @param now  - Current time in milliseconds (injectable for tests).
 */
export function mapToSnapshot(
  raw: RateLimitAllResponse,
  caps: PerplexityCaps = {},
  now: number = Date.now(),
): ProviderUsageSnapshot {
  const remainingPro = num(raw.remaining_pro);
  const remainingResearch = num(raw.remaining_research);
  const remainingLabs = num(raw.remaining_labs);

  const shortWindow: WindowUsage = {
    label: 'Pro Searches',
    utilization: utilizationFor(remainingPro, caps.pro),
    resetsAt: new Date(now + DAY_SEC * 1000).toISOString(),
    windowDurationSec: DAY_SEC,
    sublabelOverride: remainingSublabel(remainingPro, caps.pro, 'Pro left'),
  };

  // Only include the Deep Research long window if we received an explicit field,
  // so the UI doesn't show a second empty bar when the account has no deep
  // research quota at all.
  const longWindow: WindowUsage | null =
    typeof raw.remaining_research === 'number'
      ? {
          label: 'Deep Research',
          utilization: utilizationFor(remainingResearch, caps.research),
          resetsAt: new Date(now + DAY_SEC * 1000).toISOString(),
          windowDurationSec: DAY_SEC,
          sublabelOverride: remainingSublabel(remainingResearch, caps.research, 'left'),
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
      utilization: utilizationFor(remainingLabs, caps.labs),
      resetsAt: new Date(now + DAY_SEC * 1000).toISOString(),
      windowDurationSec: DAY_SEC,
      sublabelOverride: remainingSublabel(remainingLabs, caps.labs, 'left'),
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

/**
 * Utilization% from a remaining count and an inferred cap. Unknown cap (0 or
 * undefined) → 0 (empty ring) rather than a fabricated percentage.
 */
function utilizationFor(remaining: number, cap: number | undefined): number {
  if (!cap || cap <= 0) return 0;
  const used = cap - remaining;
  return Math.min(100, Math.max(0, Math.round((used / cap) * 100)));
}

/**
 * Sublabel for a quota: "X of Y left" once the cap is known, else "X <noun>".
 */
function remainingSublabel(remaining: number, cap: number | undefined, noun: string): string {
  if (cap && cap > 0) return `${remaining} of ${cap} left`;
  return `${remaining} ${noun}`;
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
