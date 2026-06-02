/**
 * Regression tests for the Gemini consumer usage parser.
 *
 * Fixtures are real batchexecute envelopes captured via chrome-devtools-mcp.
 * The jSf9Qc inner payload is:
 *   [schemaVer, [ [remaining, utilFraction, periodType, [[resetSec, nanos]]], … ], flag]
 *   - index0 = remaining compute units (counts down with use)
 *   - index1 = utilization as a 0–1 fraction (used / cap)  → utilization% = index1 * 100
 *   periodType 1 = 5-Hour, 2 = Weekly.
 *
 * The before/after pair below proves the index meaning: a task that consumed
 * 227 units moved index0 600→373 (5h) and index1 0→0.38 (= 227/600), confirming
 * index1 is the fraction — NOT index0/index1 = cap/used.
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { extractRpc, mapToSnapshot } from './gemini';

// ── Fixtures (real captures) ──────────────────────────────────────

// BEFORE the task — Free-tier account, 0% on both windows.
const FIXTURE_ZERO = `)]}'

189
[["wrb.fr","jSf9Qc","[1,[[600,0,1,[[1780373288,362509000]]],[12096,0,2,[[1780960088,362513000]]]],false]",null,null,null,"generic"],["di",193],["af.httprm",192,"-7132290681884234964",20]]
25
[["e",4,null,null,225]]`;

// AFTER the task — same account, after burning 227 compute units.
// 5h: remaining 373, fraction 0.38 (→ 38%); weekly: remaining 11869, fraction 0.01873998 (→ 2%).
const FIXTURE_USED = `)]}'

200
[["wrb.fr","jSf9Qc","[1,[[373,0.38,1,[[1780432870,316087000]]],[11869,0.01873998,2,[[1781019670,316166000]]]],false]",null,null,null,"generic"],["di",30],["af.httprm",29,"-1",20]]
25
[["e",4,null,null,200]]`;

const NOW = 1_748_800_000_000; // fixed timestamp, well before the resets

// ── extractRpc ────────────────────────────────────────────────────

test('extractRpc: decodes the inner payload for the real fixture', () => {
  const inner = extractRpc(FIXTURE_ZERO, 'jSf9Qc');
  assert.ok(Array.isArray(inner), 'expected array');
});

test('extractRpc: returns null for an unknown rpcid', () => {
  assert.equal(extractRpc(FIXTURE_ZERO, 'unknownRpc'), null);
});

test('extractRpc: returns null for an empty string', () => {
  assert.equal(extractRpc('', 'jSf9Qc'), null);
});

test('extractRpc: returns null when the inner payload is not valid JSON', () => {
  const broken = '[["wrb.fr","jSf9Qc","NOT_VALID_JSON",null,null,null,"generic"]]';
  assert.equal(extractRpc(broken, 'jSf9Qc'), null);
});

// ── Gold path: real before/after captures ────────────────────────

test('ZERO capture: both windows at 0%', () => {
  const snap = mapToSnapshot(extractRpc(FIXTURE_ZERO, 'jSf9Qc'), NOW);
  assert.equal(snap.provider, 'geminiConsumer');
  assert.equal(snap.estimated, false);
  assert.equal(snap.planLabel, 'Gemini');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.longWindow!.utilization, 0);
});

test('USED capture: 5h = 38%, weekly = 2% (index1 is the fraction, not used count)', () => {
  const snap = mapToSnapshot(extractRpc(FIXTURE_USED, 'jSf9Qc'), NOW);
  assert.equal(snap.shortWindow.utilization, 38); // round(0.38 * 100)
  assert.equal(snap.longWindow!.utilization, 2);  // round(0.01873998 * 100)
});

test('window routing + durations: 5h → shortWindow, weekly → longWindow', () => {
  const snap = mapToSnapshot(extractRpc(FIXTURE_ZERO, 'jSf9Qc'), NOW);
  assert.equal(snap.shortWindow.label, '5-Hour Window');
  assert.equal(snap.shortWindow.windowDurationSec, 5 * 3600);
  assert.equal(snap.longWindow!.label, 'Weekly');
  assert.equal(snap.longWindow!.windowDurationSec, 7 * 86400);
});

test('reset timestamps decode from epoch seconds to ISO 8601', () => {
  const snap = mapToSnapshot(extractRpc(FIXTURE_ZERO, 'jSf9Qc'), NOW);
  assert.equal(new Date(snap.shortWindow.resetsAt).getTime(), 1780373288 * 1000);
  assert.equal(new Date(snap.longWindow!.resetsAt).getTime(), 1780960088 * 1000);
});

test('capturedAt is the passed-in now', () => {
  const snap = mapToSnapshot(extractRpc(FIXTURE_ZERO, 'jSf9Qc'), NOW);
  assert.equal(snap.capturedAt, NOW);
});

// ── utilization math (index1 = 0–1 fraction) ─────────────────────

test('fraction 0.5 → 50%', () => {
  // [remaining, utilFraction, periodType, reset]
  const inner = [1, [[300, 0.5, 1, [[1780373288, 0]]]], false];
  assert.equal(mapToSnapshot(inner, NOW).shortWindow.utilization, 50);
});

test('fraction 1.0 → 100%', () => {
  const inner = [1, [[0, 1, 1, [[1780373288, 0]]]], false];
  assert.equal(mapToSnapshot(inner, NOW).shortWindow.utilization, 100);
});

test('fraction > 1 clamps to 100', () => {
  const inner = [1, [[0, 1.5, 1, [[1780373288, 0]]]], false];
  assert.equal(mapToSnapshot(inner, NOW).shortWindow.utilization, 100);
});

test('negative fraction clamps to 0', () => {
  const inner = [1, [[600, -0.1, 1, [[1780373288, 0]]]], false];
  assert.equal(mapToSnapshot(inner, NOW).shortWindow.utilization, 0);
});

test('5h and weekly carry independent fractions', () => {
  const inner = [1, [[480, 0.2, 1, [[1780373288, 0]]], [6048, 0.5, 2, [[1780960088, 0]]]], false];
  const snap = mapToSnapshot(inner, NOW);
  assert.equal(snap.shortWindow.utilization, 20);
  assert.equal(snap.longWindow!.utilization, 50);
});

// ── defensiveness ─────────────────────────────────────────────────

test('null inner → safe defaults, no throw', () => {
  const snap = mapToSnapshot(null, NOW);
  assert.equal(snap.provider, 'geminiConsumer');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.longWindow, null);
  assert.equal(snap.estimated, false);
});

test('empty array inner → safe defaults', () => {
  const snap = mapToSnapshot([], NOW);
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.longWindow, null);
});

test('missing reset → resetsAt is empty string', () => {
  const inner = [1, [[600, 0, 1, []]], false];
  assert.equal(mapToSnapshot(inner, NOW).shortWindow.resetsAt, '');
});

test('string values coerce safely to 0 (schema drift)', () => {
  const inner = [1, [[373 as unknown, '0.38' as unknown as number, 1 as unknown, [[1780432870, 0]]]], false];
  // a string fraction coerces to 0 rather than NaN
  assert.equal(mapToSnapshot(inner, NOW).shortWindow.utilization, 0);
});

test('unknown periodType lands in shortWindow (not dropped)', () => {
  const inner = [1, [[480, 0.5, 99, [[1780373288, 0]]]], false];
  const snap = mapToSnapshot(inner, NOW);
  assert.equal(snap.shortWindow.utilization, 50);
  assert.match(snap.shortWindow.label, /Window 99/);
});
