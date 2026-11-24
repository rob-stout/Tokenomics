import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
  adoptIncomingOrder,
  applyIncomingOrder,
  dropIndex,
  groupByBrand,
  effectiveOrder,
  moveInOrder,
  moveToPosition,
  nextOrderStamp,
  sortByOrder,
  stampUserOrder,
} from './provider-order';
import { PROVIDERS } from './types';

test('default PROVIDERS order matches the Mac ProviderId.allCases order (minus ids we lack)', () => {
  assert.deepEqual([...PROVIDERS], [
    'claude', 'codex', 'gemini', 'chatgpt', 'geminiConsumer', 'copilot', 'cursor',
    'midjourney', 'leonardo', 'elevenlabs', 'suno', 'udio', 'grok', 'perplexity',
  ]);
});

test('applyIncomingOrder: shared ids follow incoming; receiver-only ids keep their slots', () => {
  assert.deepEqual(
    applyIncomingOrder(['udio', 'chatgpt', 'claude'], ['claude', 'codex', 'chatgpt', 'cursor', 'suno', 'udio']),
    ['udio', 'codex', 'chatgpt', 'cursor', 'suno', 'claude'],
  );
});

test('applyIncomingOrder: empty incoming changes nothing', () => {
  assert.deepEqual(applyIncomingOrder([], ['a', 'b']), ['a', 'b']);
});

test('applyIncomingOrder: all-unknown incoming changes nothing', () => {
  assert.deepEqual(applyIncomingOrder(['x', 'y'], ['a', 'b']), ['a', 'b']);
});

test('applyIncomingOrder: unknown ids are ignored among known ones', () => {
  assert.deepEqual(applyIncomingOrder(['x', 'c', 'y', 'a'], ['a', 'b', 'c']), ['c', 'b', 'a']);
});

test('applyIncomingOrder: duplicates count once and the result is a permutation', () => {
  const result = applyIncomingOrder(['c', 'a', 'c'], ['a', 'b', 'c']);
  assert.deepEqual(result, ['c', 'b', 'a']);
  assert.deepEqual([...result].sort(), ['a', 'b', 'c']);
});

test('effectiveOrder: undefined/empty = defaults; unknown + duplicate ids dropped; missing appended', () => {
  assert.deepEqual(effectiveOrder(undefined), [...PROVIDERS]);
  assert.deepEqual(effectiveOrder([]), [...PROVIDERS]);
  const result = effectiveOrder(['udio', 'nope', 'udio', 'claude']);
  assert.deepEqual(result.slice(0, 2), ['udio', 'claude']);
  assert.equal(result.length, PROVIDERS.length);
  assert.equal(new Set(result).size, PROVIDERS.length);
});

test('moveInOrder: moves one slot, and is a no-op at the edges', () => {
  assert.deepEqual(moveInOrder(['claude', 'codex', 'gemini'] as any, 'codex' as any, -1), ['codex', 'claude', 'gemini']);
  assert.deepEqual(moveInOrder(['claude', 'codex'] as any, 'claude' as any, -1), ['claude', 'codex']);
  assert.deepEqual(moveInOrder(['claude', 'codex'] as any, 'codex' as any, 1), ['claude', 'codex']);
});

test('moveToPosition: drops the dragged row where the target sits', () => {
  assert.deepEqual(moveToPosition(['a', 'b', 'c', 'd'] as any, 'a' as any, 'c' as any), ['b', 'c', 'a', 'd']);
  assert.deepEqual(moveToPosition(['a', 'b', 'c', 'd'] as any, 'd' as any, 'b' as any), ['a', 'd', 'b', 'c']);
});

test('nextOrderStamp: whole seconds, and strictly after the previous stamp', () => {
  const now = Date.parse('2026-11-23T10:00:00.700Z');
  assert.equal(nextOrderStamp(undefined, now), '2026-11-23T10:00:00Z');
  const prev = { order: [], lastChangedAt: '2026-11-23T10:00:00Z' };
  assert.equal(nextOrderStamp(prev, now), '2026-11-23T10:00:01Z');
});

test('adoptIncomingOrder: epoch Mac order is adopted when we have none, keeping the Mac stamp', () => {
  const incoming = { order: ['udio', 'claude'], lastChangedAt: '1970-01-01T00:00:00Z' };
  const adopted = adoptIncomingOrder(undefined, incoming);
  assert.ok(adopted);
  assert.deepEqual(adopted.order.slice(0, 1), ['udio']);
  assert.equal(adopted.lastChangedAt, incoming.lastChangedAt);
});

test('adoptIncomingOrder: older or equal incoming is ignored (no ping-pong); newer wins', () => {
  const local = stampUserOrder(['claude', 'udio'] as any, undefined, Date.parse('2026-11-23T10:00:00Z'));
  assert.equal(adoptIncomingOrder(local, { order: ['udio'], lastChangedAt: '1970-01-01T00:00:00Z' }), null);
  assert.equal(adoptIncomingOrder(local, { order: ['udio'], lastChangedAt: local.lastChangedAt }), null);
  assert.equal(adoptIncomingOrder(local, undefined), null);
  const newer = adoptIncomingOrder(local, { order: ['udio', 'claude'], lastChangedAt: '2026-11-23T10:00:05Z' });
  assert.ok(newer);
  assert.equal(newer.lastChangedAt, '2026-11-23T10:00:05Z');
});

test('adoptIncomingOrder: compares real time, not strings (fraction vs no fraction)', () => {
  const local = { order: [...PROVIDERS], lastChangedAt: '2026-11-23T10:00:00.500Z' };
  // Same second, later by 500ms in real time; a string compare would get this backwards ('Z' > '.').
  assert.equal(adoptIncomingOrder(local, { order: ['udio'], lastChangedAt: '2026-11-23T10:00:00Z' }), null);
});

test('sortByOrder: follows stored order, defaults when none, stable for unknown ids', () => {
  const items = [{ id: 'udio' }, { id: 'claude' }, { id: 'copilot' }];
  assert.deepEqual(sortByOrder(items, (i) => i.id, undefined).map((i) => i.id), ['claude', 'copilot', 'udio']);
  assert.deepEqual(sortByOrder(items, (i) => i.id, ['udio']).map((i) => i.id), ['udio', 'claude', 'copilot']);
});

test('dropIndex: one slot left of a wide tab is reachable (midpoint rule)', () => {
  // Others' midpoints at 20, 60, 260 (a wide selected tab sits between 60 and 260).
  assert.equal(dropIndex([20, 60, 260], 10), 0);
  assert.equal(dropIndex([20, 60, 260], 40), 1);
  assert.equal(dropIndex([20, 60, 260], 61), 2);
  assert.equal(dropIndex([20, 60, 260], 300), 3);
  assert.equal(dropIndex([], 50), 0);
});

test('groupByBrand: moved Gemini pulls Google AI along (Mac has one Google tab)', () => {
  const order = ['claude', 'codex', 'gemini', 'leonardo', 'udio', 'geminiConsumer', 'midjourney'];
  assert.deepEqual(groupByBrand(order, 'geminiConsumer'),
    ['claude', 'codex', 'leonardo', 'udio', 'geminiConsumer', 'gemini', 'midjourney']);
});

test('groupByBrand: no anchor keeps each brand at its first member', () => {
  assert.deepEqual(groupByBrand(['chatgpt', 'claude', 'codex', 'suno']), ['chatgpt', 'codex', 'claude', 'suno']);
});

test('groupByBrand: anchor outside a pair leaves pairs at their first member', () => {
  assert.deepEqual(groupByBrand(['gemini', 'suno', 'geminiConsumer'], 'suno'), ['gemini', 'geminiConsumer', 'suno']);
});
