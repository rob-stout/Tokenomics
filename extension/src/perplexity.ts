/**
 * Perplexity usage reader.
 *
 * Polls GET https://www.perplexity.ai/rest/rate-limit/all from the service
 * worker with `credentials: 'include'` (cookie auth).
 *
 * The plan comes from /rest/user/settings (subscription_tier pro|max); sign-in
 * from /api/auth/session. Free accounts get a daily window (3 Pro Searches/day);
 * Pro/Max get remaining counts only, because Perplexity publishes no reset time.
 *
 * ── WHY THERE IS NO PLAN→CAP TABLE (unlike Leonardo) ─────────────────────────
 * This endpoint returns REMAINING counts only — no totals — AND no
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

import { isFresh, type CachedValue, type ProviderUsageSnapshot, type WindowUsage } from './snapshot';

const RATE_LIMIT_URL = 'https://www.perplexity.ai/rest/rate-limit/all';
const SESSION_URL = 'https://www.perplexity.ai/api/auth/session';
const SETTINGS_URL = 'https://www.perplexity.ai/rest/user/settings';
const DAY_SEC = 86400;

/**
 * 'free' = confirmed no paid subscription (Pro Searches are 3/day, so a daily
 * window is right). 'paid' = Pro or Max: Perplexity publishes no reset time for
 * these counts, so we show remaining numbers and describe the cadence in text.
 * 'unknown' = settings couldn't be read; treated like paid (claim no reset).
 */
export type PerplexityPlan =
  | { kind: 'free' }
  | { kind: 'paid'; label: string }
  | { kind: 'unknown' };

interface UserSettingsResponse {
  subscription_tier?: string;
  subscription_status?: string;
}

const INACTIVE_STATUSES = new Set(['none', 'canceled', 'cancelled', 'inactive', 'expired', 'unpaid']);

/** Pure (exported for tests): /rest/user/settings → plan. */
export function parsePlan(raw: UserSettingsResponse): PerplexityPlan {
  const tier = (raw.subscription_tier ?? 'none').toLowerCase();
  const status = (raw.subscription_status ?? '').toLowerCase();
  if (tier === 'pro' || tier === 'max') {
    if (INACTIVE_STATUSES.has(status)) return { kind: 'free' };
    return { kind: 'paid', label: tier === 'max' ? 'Max' : 'Pro' };
  }
  if (tier === 'none' || tier === '') return { kind: 'free' };
  // A tier we don't know (e.g. enterprise): paid-style display, no plan name.
  return { kind: 'paid', label: '' };
}

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

/**
 * /rest/rate-limit/all answers 200 with all zeros when signed out, so the HTTP
 * status can't tell "signed out" from "out of quota". /api/auth/session returns
 * `{}` when signed out. If the check itself fails we carry on rather than
 * report a false sign-out.
 */
async function assertSignedIn(): Promise<void> {
  let data: unknown;
  try {
    const res = await fetch(SESSION_URL, { credentials: 'include' });
    if (!res.ok) return;
    data = await res.json();
  } catch {
    return;
  }
  const user = (data as { user?: unknown } | null)?.user;
  if (!user) throw new AuthError(401);
}

async function fetchPlan(): Promise<PerplexityPlan | null> {
  try {
    const res = await fetch(SETTINGS_URL, { credentials: 'include' });
    if (!res.ok) return null;
    return parsePlan((await res.json()) as UserSettingsResponse);
  } catch {
    return null;
  }
}

/**
 * Plan for this poll: the cached one while fresh (~6h), else a fresh lookup.
 * A failed lookup keeps the last known plan; only a never-known plan is
 * 'unknown'. Exported for tests.
 */
export async function resolvePlan(
  prior: CachedValue<PerplexityPlan> | null,
  now: number,
  lookup: () => Promise<PerplexityPlan | null> = fetchPlan,
): Promise<CachedValue<PerplexityPlan>> {
  if (isFresh(prior, now)) return prior;
  const found = await lookup();
  if (found) return { value: found, at: now };
  return prior ?? { value: { kind: 'unknown' }, at: now - 6 * 3600 * 1000 }; // unknown: retry next poll
}

/** All counts zero = either signed out or genuinely out of quota. */
export function looksSignedOut(raw: RateLimitAllResponse): boolean {
  return (
    num(raw.remaining_pro) === 0 &&
    num(raw.remaining_research) === 0 &&
    num(raw.remaining_labs) === 0 &&
    num(raw.remaining_agentic_research) === 0
  );
}

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
  priorPlan: CachedValue<PerplexityPlan> | null = null,
): Promise<{
  snapshot: ProviderUsageSnapshot;
  caps: PerplexityCaps;
  plan: CachedValue<PerplexityPlan>;
}> {
  const now = Date.now();
  const raw = await fetchRateLimitAll();
  // Only ask the session endpoint when the numbers could mean "signed out".
  if (looksSignedOut(raw)) await assertSignedIn();
  const plan = await resolvePlan(priorPlan, now);
  const caps = mergeCaps(raw, priorCaps);
  const snapshot = mapToSnapshot(raw, caps, now, plan.value);
  return { snapshot, caps, plan };
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
 * @param plan - From /rest/user/settings. Free keeps the daily window; paid and
 *               unknown show remaining counts only (no reset, no inferred cap).
 */
export function mapToSnapshot(
  raw: RateLimitAllResponse,
  caps: PerplexityCaps = {},
  now: number = Date.now(),
  plan: PerplexityPlan = { kind: 'free' },
): ProviderUsageSnapshot {
  if (plan.kind !== 'free') return mapPaid(raw, caps, plan, now);

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

  // Only include the Deep Research long window once we've seen a quota for it.
  // Free accounts report remaining_research: 0 with no quota at all, which
  // would otherwise show an empty bar reading "0 left".
  const longWindow: WindowUsage | null =
    typeof raw.remaining_research === 'number' && (remainingResearch > 0 || (caps.research ?? 0) > 0)
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
    planLabel: 'Free',
    capturedAt: now,
    estimated: false,
  };
}

function planName(plan: PerplexityPlan): string {
  return plan.kind === 'free' ? 'Free' : plan.kind === 'paid' ? plan.label : '';
}

// Cadence text for paid plans; Perplexity gives no timestamps, so it stays text.
const PRO_CADENCE = 'resets weekly';
const RESEARCH_CADENCE = 'recovers monthly';
const WEEK_MS = 7 * 86_400_000;
const MONTH_MS = 30 * 86_400_000;

/**
 * Pro / Max: Perplexity publishes no reset time, so the numbers are ESTIMATED.
 * Utilization uses the same high-water-mark cap as Free (highest remaining ever
 * seen ~ cap), so the Mac's alerts can work; the snapshot is marked estimated.
 * The reset is a far-future placeholder (a week / a month out) because the Mac
 * drops a reading whose reset has passed; the sublabel is static text with no
 * countdown and `windowDurationSec: 0` keeps the pace dot off.
 */
function mapPaid(
  raw: RateLimitAllResponse,
  caps: PerplexityCaps,
  plan: PerplexityPlan,
  now: number,
): ProviderUsageSnapshot {
  const countWindow = (
    label: string,
    remaining: number,
    cap: number | undefined,
    cadence: string,
    placeholderMs: number,
  ): WindowUsage => ({
    label,
    utilization: utilizationFor(remaining, cap),
    resetsAt: new Date(now + placeholderMs).toISOString(),
    windowDurationSec: 0,
    sublabelOverride: `${remaining} left · ${cadence}`,
  });

  const extras: ProviderUsageSnapshot['extras'] = {};
  if (typeof raw.remaining_labs === 'number' && raw.remaining_labs > 0) {
    extras.labsRemaining = countWindow('Labs', raw.remaining_labs, caps.labs, RESEARCH_CADENCE, MONTH_MS);
  }

  return {
    provider: 'perplexity',
    shortWindow: countWindow('Pro Searches', num(raw.remaining_pro), caps.pro, PRO_CADENCE, WEEK_MS),
    longWindow:
      typeof raw.remaining_research === 'number'
        ? countWindow('Deep Research', raw.remaining_research, caps.research, RESEARCH_CADENCE, MONTH_MS)
        : null,
    extras,
    planLabel: planName(plan) || 'Perplexity',
    capturedAt: now,
    estimated: true,
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
