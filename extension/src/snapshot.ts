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

export interface ProviderUsageSnapshot {
  provider: ProviderId;
  shortWindow: WindowUsage;
  longWindow: WindowUsage | null;
  extras: { opusSevenDay?: WindowUsage; labsRemaining?: WindowUsage };
  planLabel: string;
  capturedAt: number;
  /** True when the numbers come from a local counter rather than a
   *  real usage endpoint (e.g. ChatGPT, eventually Gemini). */
  estimated?: boolean;
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
