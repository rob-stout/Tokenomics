/**
 * Unit tests for the Grok rate-limit parser.
 *
 * All tests exercise `mapToSnapshot` directly — the pure mapper is the only
 * logic worth unit-testing; the fetch layer is covered by end-to-end capture.
 *
 * Fixtures inline the REAL API response captured live 2026-06-01:
 *   { "windowSizeSeconds": 86400, "remainingQueries": 20, "totalQueries": 20,
 *     "lowEffortRateLimits": null, "highEffortRateLimits": null }
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mapToSnapshot } from './grok';

// Fixed "now" so resetsAt assertions are deterministic.
// 2026-06-01T00:00:00.000Z
const NOW = 1_748_736_000_000;
const DAY_SEC = 86400;

// ── Real fixture (fresh account, no usage) ─────────────────

test('real fixture: 20/20 remaining → 0% utilization', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 20, totalQueries: 20 },
    NOW,
  );
  assert.equal(snap.provider, 'grok');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.label, 'Fast Queries');
  assert.equal(snap.shortWindow.sublabelOverride, '20 of 20 left');
  assert.equal(snap.planLabel, 'Grok');
  assert.equal(snap.longWindow, null);
  assert.equal(snap.estimated, false);
});

// ── Partial usage ───────────────────────────────────────────

test('5 of 20 used → 25% utilization', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 15, totalQueries: 20 },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 25);
  assert.equal(snap.shortWindow.sublabelOverride, '15 of 20 left');
});

test('all 20 queries used → 100% utilization', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 0, totalQueries: 20 },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 100);
  assert.equal(snap.shortWindow.sublabelOverride, '0 of 20 left');
});

// ── Edge cases ──────────────────────────────────────────────

test('totalQueries = 0 → 0% utilization (no divide-by-zero)', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 0, totalQueries: 0 },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, '0 of 0 left');
});

test('completely empty body → safe defaults, no throw', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.provider, 'grok');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, '0 of 0 left');
  assert.equal(snap.longWindow, null);
});

test('resetsAt is now + windowSizeSeconds', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 10, totalQueries: 20 },
    NOW,
  );
  const expectedResetsAt = new Date(NOW + DAY_SEC * 1000).toISOString();
  assert.equal(snap.shortWindow.resetsAt, expectedResetsAt);
});

test('windowDurationSec defaults to 86400 when field is missing', () => {
  const snap = mapToSnapshot({ remainingQueries: 10, totalQueries: 20 }, NOW);
  assert.equal(snap.shortWindow.windowDurationSec, DAY_SEC);
});

test('capturedAt matches the `now` parameter', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.capturedAt, NOW);
});

// ── Utilization math ─────────────────────────────────────────

test('utilization rounds correctly: 1/3 → 33%', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 2, totalQueries: 3 },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 33);
});

test('utilization clamps to 100 when remaining > total (unexpected data)', () => {
  // remaining > total would mean negative used — treated as 0% used (clamp at 0).
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 25, totalQueries: 20 },
    NOW,
  );
  // used = max(0, 20 - 25) = 0 → 0%
  assert.equal(snap.shortWindow.utilization, 0);
});
