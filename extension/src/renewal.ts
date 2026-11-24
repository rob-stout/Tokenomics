/**
 * Learning a monthly reset day from the refill (shared by Leonardo and Suno).
 *
 * Some services give us a balance but no renewal date (Leonardo /me on a Free
 * account; Suno's billing/info has no `period`). Allotments do renew on the
 * account's own cycle day, so we learn that day by watching for the refill:
 * the allotment balance going UP while the purchased balance does not. From
 * then on the reset is that moment rolled forward by months.
 *
 * Callers supply two numbers per poll:
 *   balance   - the pool that the plan refills (Leonardo: subscriptionTokens,
 *               Suno: total_credits_left)
 *   purchased - the pool that only goes up when the user buys more (Leonardo:
 *               paidTokens, Suno: `credits`, the separately-bought credits)
 * A rise in `purchased` explains a rise in `balance`, so it is not a refill.
 *
 * Known limit: a service that refills daily (Suno Free is advertised as
 * "50 credits renew daily") would anchor on a daily refill and show a monthly
 * countdown that is wrong. We can't tell the two apart from balances alone;
 * the countdown is only shown once a refill has been seen.
 */

import type { ProviderUsageSnapshot } from './snapshot';
import { nextMonthlyReset } from './snapshot';

const DAY_SEC = 86400;

/** What a poll saw, minus the mapping. */
export interface RenewalPoll {
  snapshot: ProviderUsageSnapshot;
  balance: number;
  purchased: number;
  /** The API gave a real future renewal date; no need to infer one. */
  renewalKnown: boolean;
}

export interface RenewalState {
  lastBalance: number;
  lastPurchased: number;
  lastSeenAt: number;
  /** When a refill was seen. null until the first one. */
  anchorMs: number | null;
}

/** Longer than this between polls and a refill's timing is too vague to keep. */
const MAX_GAP_MS = 2 * DAY_SEC * 1000;

export function trackRenewal(
  prev: RenewalState | null,
  balance: number,
  purchased: number,
  now: number,
): RenewalState {
  let anchorMs = prev?.anchorMs ?? null;
  if (
    prev &&
    balance > prev.lastBalance &&
    purchased <= prev.lastPurchased &&
    now - prev.lastSeenAt <= MAX_GAP_MS
  ) {
    anchorMs = now;
  }
  return { lastBalance: balance, lastPurchased: purchased, lastSeenAt: now, anchorMs };
}

/**
 * With a learned cycle day, set the real reset and add it to the sublabel
 * ("150 tokens left · resets in 16d"). Without one, leave the snapshot as is.
 */
export function applyRenewal(
  poll: RenewalPoll,
  state: RenewalState,
  now: number,
): ProviderUsageSnapshot {
  if (poll.renewalKnown || state.anchorMs === null) return poll.snapshot;
  const resetsAt = nextMonthlyReset(state.anchorMs, now);
  const days = Math.max(0, Math.floor((new Date(resetsAt).getTime() - now) / (DAY_SEC * 1000)));
  const when = days === 0 ? 'resets today' : days === 1 ? 'resets tomorrow' : `resets in ${days}d`;
  const w = poll.snapshot.shortWindow;
  return {
    ...poll.snapshot,
    shortWindow: {
      ...w,
      resetsAt,
      windowDurationSec: 30 * DAY_SEC,
      sublabelOverride: w.sublabelOverride ? `${w.sublabelOverride} · ${when}` : undefined,
    },
  };
}
