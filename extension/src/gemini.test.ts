/**
 * Regression tests for the Gemini consumer usage parser.
 *
 * The fixture is the actual batchexecute envelope captured 2026-06-01 from a
 * Free-tier account with 0% usage. Inner payload:
 *   [1,[[600,0,1,[[1780373288,362509000]]],[12096,0,2,[[1780960088,362513000]]]],false]
 *   periodType 1 = 5-Hour (cap 600), periodType 2 = Weekly (cap 12096), both 0 used.
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { extractRpc, mapToSnapshot } from './gemini';

// ── Fixtures ──────────────────────────────────────────────────────

// Real batchexecute envelope captured 2026-06-01 via chrome-devtools-mcp.
// The envelope begins with )]}\' on its own line, then length-prefixed chunks.
const REAL_FIXTURE = `)]}'

189
[["wrb.fr","jSf9Qc","[1,[[600,0,1,[[1780373288,362509000]]],[12096,0,2,[[1780960088,362513000]]]],false]",null,null,null,"generic"],["di",193],["af.httprm",192,"-7132290681884234964",20]]
25
[["e",4,null,null,225]]`;

// Pinned "now" for deterministic utilization assertions.
const NOW = 1_748_800_000_000; // arbitrary fixed timestamp well before the resets

// ── extractRpc ────────────────────────────────────────────────────

test('extractRpc: returns decoded inner payload for the real fixture', () => {
  const inner = extractRpc(REAL_FIXTURE, 'jSf9Qc');
  assert.ok(inner !== null, 'expected non-null result');
  assert.ok(Array.isArray(inner), 'expected array');
});

test('extractRpc: returns null for an unknown rpcid', () => {
  assert.equal(extractRpc(REAL_FIXTURE, 'unknownRpc'), null);
});

test('extractRpc: returns null for a completely empty string', () => {
  assert.equal(extractRpc('', 'jSf9Qc'), null);
});

test('extractRpc: returns null when the inner payload is not valid JSON', () => {
  const broken = '[["wrb.fr","jSf9Qc","NOT_VALID_JSON",null,null,null,"generic"]]';
  assert.equal(extractRpc(broken, 'jSf9Qc'), null);
});

// ── mapToSnapshot — 0% case (real fixture) ────────────────────────

test('0% case: both windows at 0 utilization', () => {
  const inner = extractRpc(REAL_FIXTURE, 'jSf9Qc');
  assert.ok(inner !== null);
  const snap = mapToSnapshot(inner, NOW);

  assert.equal(snap.provider, 'geminiConsumer');
  assert.equal(snap.estimated, false);
  assert.equal(snap.planLabel, 'Gemini');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.ok(snap.longWindow !== null, 'expected a long window');
  assert.equal(snap.longWindow!.utilization, 0);
});

test('0% case: shortWindow is the 5-Hour window', () => {
  const inner = extractRpc(REAL_FIXTURE, 'jSf9Qc');
  const snap = mapToSnapshot(inner!, NOW);

  assert.equal(snap.shortWindow.label, '5-Hour Window');
  assert.equal(snap.shortWindow.windowDurationSec, 5 * 3600);
});

test('0% case: longWindow is the Weekly window', () => {
  const inner = extractRpc(REAL_FIXTURE, 'jSf9Qc');
  const snap = mapToSnapshot(inner!, NOW);

  assert.ok(snap.longWindow !== null);
  assert.equal(snap.longWindow!.label, 'Weekly');
  assert.equal(snap.longWindow!.windowDurationSec, 7 * 86400);
});

test('0% case: reset timestamps are ISO 8601 strings from epoch seconds', () => {
  const inner = extractRpc(REAL_FIXTURE, 'jSf9Qc');
  const snap = mapToSnapshot(inner!, NOW);

  // Epoch 1780373288 → 5h window reset
  const shortReset = new Date(snap.shortWindow.resetsAt).getTime();
  assert.equal(shortReset, 1780373288 * 1000);

  // Epoch 1780960088 → weekly reset
  const longReset = new Date(snap.longWindow!.resetsAt).getTime();
  assert.equal(longReset, 1780960088 * 1000);
});

// ── mapToSnapshot — utilization math ─────────────────────────────

test('50% utilization: 300 used of 600 cap → 50', () => {
  // Construct an inner payload with non-zero usage.
  const inner = [1, [[600, 300, 1, [[1780373288, 0]]], [12096, 0, 2, [[1780960088, 0]]]], false];
  const snap = mapToSnapshot(inner, NOW);
  assert.equal(snap.shortWindow.utilization, 50);
});

test('100% utilization: cap and used equal', () => {
  const inner = [1, [[600, 600, 1, [[1780373288, 0]]], [12096, 12096, 2, [[1780960088, 0]]]], false];
  const snap = mapToSnapshot(inner, NOW);
  assert.equal(snap.shortWindow.utilization, 100);
  assert.equal(snap.longWindow!.utilization, 100);
});

test('utilization clamps to 100 when used > cap', () => {
  const inner = [1, [[600, 9999, 1, [[1780373288, 0]]]], false];
  const snap = mapToSnapshot(inner, NOW);
  assert.equal(snap.shortWindow.utilization, 100);
});

test('utilization is 0 when cap is 0 (avoids divide-by-zero)', () => {
  const inner = [1, [[0, 500, 1, [[1780373288, 0]]]], false];
  const snap = mapToSnapshot(inner, NOW);
  assert.equal(snap.shortWindow.utilization, 0);
});

test('capturedAt is the passed-in now value', () => {
  const inner = extractRpc(REAL_FIXTURE, 'jSf9Qc');
  const snap = mapToSnapshot(inner!, NOW);
  assert.equal(snap.capturedAt, NOW);
});

// ── mapToSnapshot — 5h vs weekly split ───────────────────────────

test('periodType 1 → shortWindow, periodType 2 → longWindow', () => {
  // Only the 5h window present.
  const inner5h = [1, [[600, 120, 1, [[1780373288, 0]]]], false];
  const snap5h = mapToSnapshot(inner5h, NOW);
  assert.equal(snap5h.shortWindow.utilization, 20); // 120/600 = 20%
  assert.equal(snap5h.longWindow, null);

  // Only the weekly window present.
  const innerWeekly = [1, [[12096, 6048, 2, [[1780960088, 0]]]], false];
  const snapWeekly = mapToSnapshot(innerWeekly, NOW);
  assert.equal(snapWeekly.longWindow!.utilization, 50); // 6048/12096 = 50%
});

// ── mapToSnapshot — defensiveness ────────────────────────────────

test('completely null/empty inner → safe defaults, no throw', () => {
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

test('windows array present but all entries missing reset → resetsAt is empty string', () => {
  const inner = [1, [[600, 0, 1, []]], false];
  const snap = mapToSnapshot(inner, NOW);
  assert.equal(snap.shortWindow.resetsAt, '');
});

test('window entry with string values does not crash (type drift scenario)', () => {
  // Simulate a schema change where values come back as strings.
  // Our num() helper should return 0 for non-finite/non-number values.
  const inner = [1, [['600' as unknown as number, '0' as unknown as number, 1 as unknown, [[1780373288, 0]]]], false];
  const snap = mapToSnapshot(inner, NOW);
  // cap coerces to 0 → utilization = 0 (avoids NaN)
  assert.equal(snap.shortWindow.utilization, 0);
});

test('unknown periodType lands in shortWindow (not silently dropped)', () => {
  // periodType 99 is unknown — falls to the else branch (shortWindow).
  const inner = [1, [[600, 300, 99, [[1780373288, 0]]]], false];
  const snap = mapToSnapshot(inner, NOW);
  // Utilization should still be calculated correctly.
  assert.equal(snap.shortWindow.utilization, 50);
  assert.match(snap.shortWindow.label, /Window 99/);
});
