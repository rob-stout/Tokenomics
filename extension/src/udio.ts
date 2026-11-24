/**
 * Udio usage reader.
 *
 * Auth: the signed-in browser session. Udio uses Supabase SSR auth (cookie
 * `sb-ssr-production-auth-token`, SameSite=Lax) plus an httpOnly
 * `feather__session`; both ride along on a same-site fetch with
 * `credentials: 'include'`, exactly like the Grok/Perplexity readers. No token
 * is read or stored by the extension.
 *
 * ── API (real capture, Free account, 2026-11-23 — fixtures/udio-*.json) ──────
 * GET https://www.udio.com/api/users/current/api-usage
 *   { data: { tier: "free", daily_used: 2, daily_throttle_limit: 10,
 *             monthly_used: 2, monthly_limit: 310,
 *             start_day: "2026-11-23T15:17:51Z",     // daily window began
 *             start_month: "2026-11-23T15:17:51Z",   // monthly window began
 *             renew_time: "2026-12-23T15:17:51Z",    // next monthly reset
 *             concurrent_*, two_min_daily_*, discretionary, ... } }
 * GET https://www.udio.com/api/subscriptions
 *   { plan: "free", isActive: false, proPlan: false, paidPlan: false, ... }
 *
 * ── MAPPING ──────────────────────────────────────────────────────────────────
 *  shortWindow = Monthly  (monthly_used / monthly_limit, reset = renew_time)
 *  longWindow  = Daily    (daily_used / daily_throttle_limit,
 *                          reset = start_day + 24h)
 * Monthly goes first because it is the real allowance: the Mac app, widgets and
 * toolbar badge all key off shortWindow, and every other monthly-credit
 * provider (Suno, Leonardo, ElevenLabs) is shown the same way. The daily cap is
 * a throttle layered on top; it still gets its own bar in the popup.
 *
 * Neither window sets sublabelOverride, so the popup shows a live reset
 * countdown computed from the real dates.
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

const USAGE_URL = 'https://www.udio.com/api/users/current/api-usage';
const SUBSCRIPTIONS_URL = 'https://www.udio.com/api/subscriptions';
const DAY_MS = 86_400_000;
const DEFAULT_MONTH_SEC = 30 * 86400;

export class AuthError extends Error {
  constructor(status: number) {
    super(`Not signed in to udio.com (status ${status})`);
    this.name = 'AuthError';
  }
}

export class RateLimitError extends Error {
  constructor() {
    super('udio.com rate limited the request');
    this.name = 'RateLimitError';
  }
}

// ── Response shapes ──────────────────────────────────────────

export interface UdioUsage {
  tier?: string;
  daily_used?: number;
  daily_throttle_limit?: number;
  monthly_used?: number;
  monthly_limit?: number;
  start_day?: string;
  start_month?: string;
  renew_time?: string;
}

export interface UdioSubscription {
  plan?: string;
}

// ── Fetch layer ──────────────────────────────────────────────

async function getJson(url: string): Promise<unknown> {
  const res = await fetch(url, { credentials: 'include', headers: { accept: 'application/json' } });
  if (res.status === 401 || res.status === 403) throw new AuthError(res.status);
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`udio fetch failed: ${res.status} ${url}`);
  return res.json();
}

/**
 * Fetch Udio usage + plan. The plan lookup is best-effort: if it fails the
 * usage numbers still show, with the plan taken from `tier`.
 */
export async function fetchUdioUsage(): Promise<ProviderUsageSnapshot> {
  const [usageBody, subscription] = await Promise.all([
    getJson(USAGE_URL),
    getJson(SUBSCRIPTIONS_URL).catch((err: unknown) => {
      if (err instanceof AuthError || err instanceof RateLimitError) throw err;
      return null;
    }),
  ]);
  const usage = isRecord(usageBody) && isRecord(usageBody.data) ? (usageBody.data as UdioUsage) : null;
  if (!usage) throw new Error('udio api-usage: unexpected response shape');
  return mapToSnapshot(usage, isRecord(subscription) ? (subscription as UdioSubscription) : null, Date.now());
}

// ── Mapper ───────────────────────────────────────────────────

/**
 * Pure mapper. Exported for unit testing. Never throws.
 *
 * Daily: if start_day + 24h is already past, the server has rolled the window
 * (it re-bases on the next generation), so show 0 used and the next 24h
 * boundary rather than a stale count.
 */
export function mapToSnapshot(
  usage: UdioUsage,
  subscription: UdioSubscription | null,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  const monthly = monthlyWindow(usage, now);
  const daily = dailyWindow(usage, now);
  return {
    provider: 'udio',
    shortWindow: monthly,
    longWindow: daily,
    extras: {},
    planLabel: planLabel(subscription?.plan ?? usage.tier),
    capturedAt: now,
    estimated: false,
  };
}

function monthlyWindow(usage: UdioUsage, now: number): WindowUsage {
  const renewMs = parseMs(usage.renew_time);
  const startMs = parseMs(usage.start_month);
  const durationSec =
    renewMs !== null && startMs !== null && renewMs > startMs
      ? Math.round((renewMs - startMs) / 1000)
      : DEFAULT_MONTH_SEC;
  return {
    label: 'Monthly',
    utilization: percent(usage.monthly_used, usage.monthly_limit),
    resetsAt: new Date(renewMs ?? now + DEFAULT_MONTH_SEC * 1000).toISOString(),
    windowDurationSec: durationSec,
  };
}

function dailyWindow(usage: UdioUsage, now: number): WindowUsage {
  const startMs = parseMs(usage.start_day);
  let resetMs = (startMs ?? now) + DAY_MS;
  let used = usage.daily_used;
  if (startMs !== null && resetMs <= now) {
    // Window already rolled: next boundary on the same 24h grid, nothing used yet.
    resetMs = startMs + (Math.floor((now - startMs) / DAY_MS) + 1) * DAY_MS;
    used = 0;
  }
  return {
    label: 'Daily',
    utilization: percent(used, usage.daily_throttle_limit),
    resetsAt: new Date(resetMs).toISOString(),
    windowDurationSec: DAY_MS / 1000,
  };
}

// ── Helpers ──────────────────────────────────────────────────

/** "free" → "Free", "pro_monthly" → "Pro"; anything empty → "Udio". */
function planLabel(plan: string | undefined): string {
  if (typeof plan !== 'string' || plan.trim() === '') return 'Udio';
  const first = plan.trim().split(/[_\s-]/)[0] ?? '';
  return first.charAt(0).toUpperCase() + first.slice(1).toLowerCase() || 'Udio';
}

function percent(used: unknown, limit: unknown): number {
  const u = typeof used === 'number' && Number.isFinite(used) ? used : 0;
  const l = typeof limit === 'number' && Number.isFinite(limit) ? limit : 0;
  if (l <= 0) return 0;
  return Math.min(100, Math.max(0, Math.round((u / l) * 100)));
}

function parseMs(date: string | undefined): number | null {
  if (typeof date !== 'string' || date.length === 0) return null;
  const ms = Date.parse(date);
  return Number.isFinite(ms) ? ms : null;
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}
