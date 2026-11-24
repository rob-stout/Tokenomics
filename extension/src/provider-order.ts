/**
 * Pure rules for the provider tab order and its sync with the Mac app.
 * No browser APIs, so tests (and bridge.ts) can import it freely.
 * Swift twin: Tokenomics/Models/ProviderOrderSync.swift — keep the two in step.
 */

import type { ProviderOrderSetting } from './bridge-types';
import { PROVIDERS, type ProviderId } from './types';

/**
 * The order to display: the saved order (unknown ids and duplicates dropped),
 * with any provider it doesn't mention appended in default order. Nothing saved
 * = the default `PROVIDERS` order, which mirrors the Mac app's.
 */
export function effectiveOrder(stored: readonly string[] | undefined): ProviderId[] {
  const known = new Set<string>(PROVIDERS);
  const result: ProviderId[] = [];
  for (const id of stored ?? []) {
    if (known.has(id) && !result.includes(id as ProviderId)) result.push(id as ProviderId);
  }
  for (const id of PROVIDERS) if (!result.includes(id)) result.push(id);
  return result;
}

/**
 * Reorders `current` to follow `incoming` for ids both sides know.
 *
 * Rule: take the slots (positions) in `current` held by ids that also appear in
 * `incoming`, and refill those slots, in slot order, with those ids in `incoming`'s
 * relative order. Ids missing from `incoming` keep their exact slots; ids only in
 * `incoming` are ignored; duplicates in `incoming` count once (first wins).
 * The result is always a permutation of `current`.
 */
export function applyIncomingOrder(incoming: readonly string[], current: readonly string[]): string[] {
  const currentSet = new Set(current);
  const shared: string[] = [];
  for (const id of incoming) if (currentSet.has(id) && !shared.includes(id)) shared.push(id);
  const sharedSet = new Set(shared);

  let next = 0;
  return current.map((id) => (sharedSet.has(id) ? shared[next++] : id));
}

/** Moves `id` by `delta` slots (-1 = earlier). Returns the same array when it can't move. */
export function moveInOrder(order: readonly ProviderId[], id: ProviderId, delta: number): ProviderId[] {
  const from = order.indexOf(id);
  const to = from + delta;
  if (from < 0 || to < 0 || to >= order.length) return [...order];
  const next = [...order];
  next.splice(from, 1);
  next.splice(to, 0, id);
  return next;
}

/** Moves the `fromId` row to where `toId` sits (drag and drop). */
export function moveToPosition(order: readonly ProviderId[], fromId: ProviderId, toId: ProviderId): ProviderId[] {
  const from = order.indexOf(fromId);
  const to = order.indexOf(toId);
  return from < 0 || to < 0 ? [...order] : moveInOrder(order, fromId, to - from);
}

function toMillis(iso: string): number {
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? 0 : ms;
}

/**
 * Stamp for a user reorder: whole seconds (the Mac's date coding drops fractions)
 * and strictly after the previous stamp, so two quick reorders both win.
 */
export function nextOrderStamp(previous: ProviderOrderSetting | undefined, nowMs: number = Date.now()): string {
  const prevSec = previous ? Math.floor(toMillis(previous.lastChangedAt) / 1000) : -1;
  const sec = Math.max(Math.floor(nowMs / 1000), prevSec + 1);
  return new Date(sec * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** A user reorder, ready to store and sync. */
export function stampUserOrder(
  order: readonly ProviderId[],
  previous: ProviderOrderSetting | undefined,
  nowMs: number = Date.now(),
): ProviderOrderSetting {
  return { order: [...order], lastChangedAt: nextOrderStamp(previous, nowMs) };
}

/**
 * Adopts the Mac's order if it is strictly newer than ours (no local order counts as
 * oldest). Returns the setting to store, or null for "keep what we have". The stored
 * setting keeps the INCOMING timestamp, so when we echo it back the Mac sees it as
 * not-newer and does nothing — that is what prevents ping-pong.
 */
export function adoptIncomingOrder(
  local: ProviderOrderSetting | undefined,
  incoming: ProviderOrderSetting | undefined,
): ProviderOrderSetting | null {
  if (!incoming) return null;
  if (local && toMillis(incoming.lastChangedAt) <= toMillis(local.lastChangedAt)) return null;
  return {
    order: applyIncomingOrder(incoming.order, effectiveOrder(local?.order)),
    lastChangedAt: incoming.lastChangedAt,
  };
}

/** Sorts items into the effective order (unlisted ids last, stable). */
export function sortByOrder<T>(
  items: readonly T[],
  idOf: (item: T) => string,
  stored: readonly string[] | undefined,
): T[] {
  const rank = new Map<string, number>(effectiveOrder(stored).map((id, i) => [id, i]));
  return [...items].sort((a, b) => (rank.get(idOf(a)) ?? 1e9) - (rank.get(idOf(b)) ?? 1e9));
}
