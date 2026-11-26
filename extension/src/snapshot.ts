import type { ProviderId } from './types';

/**
 * Mirror of Tokenomics/Models/Provider.swift WindowUsage. Utilization is in
 * 0–100, matching the Mac model — the Claude API returns 0–1 and the reader
 * converts on the way in.
 */
export interface WindowUsage {
  label: string;
  utilization: number;
  resetsAt: string;
  windowDurationSec: number;
  sublabelOverride?: string;
}

export interface UsageCredits {
  /** Major units (dollars), already scaled by the currency exponent. */
  used: number;
  /** null when the account has no spend cap. */
  limit: number | null;
  currency: string;
}

export interface ProviderUsageSnapshot {
  provider: ProviderId;
  shortWindow: WindowUsage;
  longWindow: WindowUsage | null;
  extras: {
    opusSevenDay?: WindowUsage;
    labsRemaining?: WindowUsage;
    /** Per-model weekly caps (Claude `weekly_scoped` limits), e.g. "Fable Weekly". */
    scopedWeekly?: WindowUsage[];
    /** Claude "usage credits" (pay-as-you-go overage). Only set when enabled. */
    usageCredits?: UsageCredits;
  };
  planLabel: string;
  capturedAt: number;
  /** True when the numbers come from a local counter rather than a
   *  real usage endpoint (e.g. ChatGPT, eventually Gemini). */
  estimated?: boolean;
}

/** A value remembered with the time it was fetched (for plan lookups that rarely change). */
export interface CachedValue<T> {
  value: T;
  at: number;
}

/** Plan lookups are cached this long to save a request per poll. */
export const PLAN_CACHE_TTL_MS = 6 * 3600 * 1000;

export function isFresh<T>(c: CachedValue<T> | null | undefined, now: number): c is CachedValue<T> {
  return !!c && now - c.at < PLAN_CACHE_TTL_MS && now >= c.at;
}

export type AuthState = 'authenticated' | 'unauthenticated' | 'unknown';

export interface BackoffState {
  until: number;
  nextDelayMs: number;
}

export function computePace(usage: WindowUsage, now: number = Date.now()): number {
  if (usage.windowDurationSec <= 0) return 0;
  const resetsAtMs = new Date(usage.resetsAt).getTime();
  if (Number.isNaN(resetsAtMs)) return 0;
  const remainingMs = Math.max(0, resetsAtMs - now);
  const elapsedMs = usage.windowDurationSec * 1000 - Math.min(remainingMs, usage.windowDurationSec * 1000);
  const pace = elapsedMs / (usage.windowDurationSec * 1000);
  return Math.min(Math.max(pace, 0), 1);
}

export function formatTimeUntilReset(usage: WindowUsage, now: number = Date.now()): string {
  if (usage.sublabelOverride) return usage.sublabelOverride;

  const resetsAtMs = new Date(usage.resetsAt).getTime();
  if (Number.isNaN(resetsAtMs)) return '';

  const remainingMs = resetsAtMs - now;
  if (remainingMs <= 0) return 'Resetting now';

  const totalMinutes = Math.floor(remainingMs / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;

  if (hours >= 24) {
    const resetDate = new Date(resetsAtMs);
    const nowDate = new Date(now);
    const sameDay = resetDate.toDateString() === nowDate.toDateString();
    const tomorrow = new Date(now + 24 * 60 * 60 * 1000);
    const isTomorrow = resetDate.toDateString() === tomorrow.toDateString();

    if (sameDay) return 'Resets today';
    if (isTomorrow) return 'Resets tomorrow';

    const days = Math.floor(hours / 24);
    return `Resets in ${days}d`;
  }
  if (hours > 0) return `Resets in ${hours}h ${minutes}m`;
  return `Resets in ${minutes}m`;
}

/**
 * Free accounts keep reporting the first reset date long after it passed
 * (seen live: a May 1 date in November). Credits still refresh monthly on
 * that day, so roll a past date forward by calendar months instead of
 * inventing "30 days from now", which would never count down.
 * Missing date: fall back to now + 30d (the pace marker is then ~0, hidden).
 */
export function nextMonthlyReset(resetMs: number, now: number): string {
  if (resetMs <= 0) return new Date(now + 30 * 86_400_000).toISOString();
  const d = new Date(resetMs);
  const day = d.getUTCDate();
  for (let i = 0; d.getTime() <= now && i < 600; i++) {
    d.setUTCDate(1);
    d.setUTCMonth(d.getUTCMonth() + 1);
    const lastDay = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
    d.setUTCDate(Math.min(day, lastDay));
  }
  return d.toISOString();
}
