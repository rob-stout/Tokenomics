/**
 * Suno usage reader — parsing + mapping only.
 *
 * ── HOW THE DATA GETS HERE ───────────────────────────────────────────────────
 * Suno's API wants a short-lived (~60 s) Clerk session JWT as
 * `Authorization: Bearer <jwt>`. suno.com does NOT expose `window.Clerk`, but
 * Clerk keeps that JWT in the non-httpOnly cookie `__session` (domain
 * .suno.com) and refreshes it while a suno.com tab is open. So the content
 * script (content/suno-watch.ts, ISOLATED world) reads `document.cookie`,
 * calls the billing endpoint from the page's origin, and hands ONLY the
 * numbers picked by `pickBilling` to the service worker. The token is used for
 * exactly one request and is never posted, stored, or logged.
 *
 *   GET https://studio-api.prod.suno.com/api/billing/info/
 *
 * ── VERIFIED RESPONSE (real capture, Free account, 2026-11-23) ───────────────
 * See fixtures/suno-billing-info.json (ids redacted). Fields we use:
 *   total_credits_left  300      credits available now
 *   monthly_limit       300      the plan's monthly allowance
 *   monthly_usage       0        credits spent this month
 *   credits             0        separately-bought credits (assumption below)
 *   is_active           false    paid subscription active
 *   subscription_type   false    false on Free; presumably a plan string when paid
 * Fields we deliberately ignore:
 *   plans[]            the catalogue of ALL plans, not the user's plan
 *   credit_rate_limit  a short-term rate limiter (200 available, +20 / 600 s)
 *   the download / visual credit packs, models, promotions, ...
 * There is NO `period` and NO `plan` object, so no reset date comes from the
 * API: it is learned from the refill (see renewal.ts).
 *
 * ── ASSUMPTIONS (not provable from a single Free-account capture) ────────────
 *  - `credits` is the pool that only grows when the user buys credits, so for
 *    renewal tracking: balance = total_credits_left, purchased = credits.
 *  - On paid plans `subscription_type` is a string naming the plan.
 *  - Free is advertised as "50 credits renew daily" yet the capture shows a
 *    300 monthly limit; if the balance really refills daily, the learned
 *    monthly countdown would be wrong (see the note in renewal.ts).
 */

import type { RenewalPoll } from './renewal';
import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

const MONTH_SEC = 30 * 86400;

/** The only fields we keep from the billing response. */
export interface SunoBilling {
  totalCreditsLeft?: number;
  monthlyLimit?: number;
  monthlyUsage?: number;
  /** Separately-bought credits; only used to tell a purchase from a refill. */
  credits?: number;
  isActive?: boolean;
  /** Present only when `subscription_type` is a non-empty string. */
  subscriptionType?: string;
}

// ── Session cookie ───────────────────────────────────────────────────────────

/**
 * Pull the Clerk session JWT out of a `document.cookie` string. Returns null
 * unless the value looks like a JWT (three dot-separated base64url parts), so
 * a stray or empty cookie never goes out as a Bearer token.
 */
export function readSessionToken(cookieString: string): string | null {
  for (const part of cookieString.split(';')) {
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    if (part.slice(0, eq).trim() !== '__session') continue;
    const value = part.slice(eq + 1).trim();
    return /^[\w-]+\.[\w-]+\.[\w-]+$/.test(value) ? value : null;
  }
  return null;
}

// ── Whitelist (runs in the page, before anything crosses to the extension) ───

/**
 * Reduce an arbitrary billing JSON to the handful of fields we display.
 * Everything else (ids, prices, payment details) is dropped here, in the page.
 * Pure; tolerant of any input shape.
 */
export function pickBilling(raw: unknown): SunoBilling {
  const obj = isRecord(raw) ? raw : {};
  const out: SunoBilling = {};

  const left = finite(obj.total_credits_left);
  if (left !== undefined) out.totalCreditsLeft = left;
  const limit = finite(obj.monthly_limit);
  if (limit !== undefined) out.monthlyLimit = limit;
  const usage = finite(obj.monthly_usage);
  if (usage !== undefined) out.monthlyUsage = usage;
  const credits = finite(obj.credits);
  if (credits !== undefined) out.credits = credits;
  if (typeof obj.is_active === 'boolean') out.isActive = obj.is_active;
  if (typeof obj.subscription_type === 'string' && obj.subscription_type.trim() !== '') {
    out.subscriptionType = obj.subscription_type.trim();
  }
  return out;
}

// ── Mapper ───────────────────────────────────────────────────────────────────

/**
 * Pure mapper from picked billing fields to a ProviderUsageSnapshot.
 * Exported for unit testing. Never throws.
 *
 * utilization = monthly_usage / monthly_limit. If monthly_usage is absent but
 * credits-left and the limit are known, usage = limit - left. With no usable
 * limit the ring stays at 0 and the sublabel shows credits left (or nothing).
 *
 * resetsAt is a placeholder (now + 30d) because the API gives no reset date;
 * applyRenewal replaces it once a refill has been observed.
 */
export function mapToSnapshot(
  billing: SunoBilling,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  const limit = positive(billing.monthlyLimit);
  const left = nonNegative(billing.totalCreditsLeft);
  const usage =
    nonNegative(billing.monthlyUsage) ??
    (limit !== undefined && left !== undefined ? Math.max(0, limit - left) : undefined);

  const utilization =
    limit !== undefined && usage !== undefined
      ? Math.min(100, Math.max(0, Math.round((usage / limit) * 100)))
      : 0;

  const shortWindow: WindowUsage = {
    label: 'Credits',
    utilization,
    resetsAt: new Date(now + MONTH_SEC * 1000).toISOString(),
    windowDurationSec: MONTH_SEC,
    ...(left !== undefined ? { sublabelOverride: `${formatCount(left)} credits left` } : {}),
  };

  return {
    provider: 'suno',
    shortWindow,
    longWindow: null,
    extras: {},
    planLabel: planLabel(billing),
    capturedAt: now,
    estimated: false,
  };
}

/** Inputs for renewal tracking, or null when the response had no balance. */
export function toRenewalPoll(billing: SunoBilling, now: number = Date.now()): RenewalPoll | null {
  if (nonNegative(billing.totalCreditsLeft) === undefined) return null;
  return {
    snapshot: mapToSnapshot(billing, now),
    balance: billing.totalCreditsLeft ?? 0,
    purchased: billing.credits ?? 0,
    renewalKnown: false, // the API never sends a reset date
  };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/** "Free" for inactive / non-subscribers, the plan string when paid, else "Suno". */
function planLabel(billing: SunoBilling): string {
  if (billing.isActive === false) return 'Free';
  if (billing.subscriptionType) {
    const t = billing.subscriptionType;
    return t.charAt(0).toUpperCase() + t.slice(1);
  }
  // `subscription_type: false` is dropped by pickBilling; with is_active also
  // absent we can't tell Free from "field missing", so stay generic.
  return 'Suno';
}

function formatCount(n: number): string {
  return Math.round(n).toLocaleString('en-US');
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** Finite number from a number or numeric string; undefined otherwise. */
function finite(v: unknown): number | undefined {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const parsed = Number(v);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

function nonNegative(v: number | undefined): number | undefined {
  return v !== undefined && v >= 0 ? v : undefined;
}

function positive(v: number | undefined): number | undefined {
  return v !== undefined && v > 0 ? v : undefined;
}
