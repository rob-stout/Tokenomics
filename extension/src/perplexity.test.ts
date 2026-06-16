/**
 * Unit tests for the Perplexity rate-limit parser.
 *
 * Exercises `mapToSnapshot` (pure mapper) and `mergeCaps` (high-water-mark
 * cap inference) directly.
 *
 * Real API response (free account, 2026-06-01):
 *   { "free_queries": { "available": true, "remaining_detail": { "kind": "not_provided" } },
 *     "remaining_agentic_research": 0, "remaining_labs": 0, "remaining_pro": 5,
 *     "remaining_research": 0, "model_specific_limits": {}, "sources": { ... } }
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mapToSnapshot, mergeCaps } from './perplexity';

// Fixed "now" so resetsAt assertions are deterministic.
// 2026-06-01T00:00:00.000Z
const NOW = 1_748_736_000_000;
const DAY_SEC = 86400;

// ── Real fixture (free account) ────────────────────────────

test('real fixture: 5 pro remaining, no cap yet → 0% ring, remaining-only sublabel', () => {
  const snap = mapToSnapshot(
    {
      remaining_pro: 5,
      remaining_research: 0,
      remaining_labs: 0,
      remaining_agentic_research: 0,
    },
    {}, // no caps observed yet
    NOW,
  );
  assert.equal(snap.provider, 'perplexity');
  assert.equal(snap.shortWindow.label, 'Pro Searches');
  assert.equal(snap.shortWindow.utilization, 0); // no cap yet → 0
  assert.equal(snap.shortWindow.sublabelOverride, '5 Pro left');
  assert.equal(snap.planLabel, 'Perplexity');
  assert.equal(snap.capturedAt, NOW);
  assert.equal(snap.estimated, false);
});

// ── High-water-mark cap inference (mergeCaps) ───────────────

test('mergeCaps: first observation sets caps from remaining', () => {
  const caps = mergeCaps({ remaining_pro: 5, remaining_research: 2, remaining_labs: 1 }, {});
  assert.deepEqual(caps, { pro: 5, research: 2, labs: 1 });
});

test('mergeCaps: keeps the maximum ever seen (cap only grows)', () => {
  const caps = mergeCaps({ remaining_pro: 3 }, { pro: 5 });
  assert.equal(caps.pro, 5); // 3 < 5, cap stays at the high-water-mark
});

test('mergeCaps: a higher remaining raises the cap', () => {
  const caps = mergeCaps({ remaining_pro: 300 }, { pro: 5 });
  assert.equal(caps.pro, 300);
});

test('mergeCaps: a missing field never resets a known cap', () => {
  const caps = mergeCaps({ remaining_research: 2 }, { pro: 5, research: 2 });
  assert.equal(caps.pro, 5); // remaining_pro absent → untouched
  assert.equal(caps.research, 2);
});

// ── Utilization ring (cap known) ────────────────────────────

test('cap known: utilization = (cap - remaining) / cap', () => {
  // Cap 5, 2 left → 3 used → 60%.
  const snap = mapToSnapshot({ remaining_pro: 2 }, { pro: 5 }, NOW);
  assert.equal(snap.shortWindow.utilization, 60);
  assert.equal(snap.shortWindow.sublabelOverride, '2 of 5 left');
});

test('cap known + full quota → 0% utilization', () => {
  const snap = mapToSnapshot({ remaining_pro: 5 }, { pro: 5 }, NOW);
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, '5 of 5 left');
});

test('cap known + empty quota → 100% utilization', () => {
  const snap = mapToSnapshot({ remaining_pro: 0 }, { pro: 5 }, NOW);
  assert.equal(snap.shortWindow.utilization, 100);
  assert.equal(snap.shortWindow.sublabelOverride, '0 of 5 left');
});

test('remaining above an under-calibrated cap clamps to 0%, never negative', () => {
  // Defensive: remaining (8) > stored cap (5) should never yield negative util.
  const snap = mapToSnapshot({ remaining_pro: 8 }, { pro: 5 }, NOW);
  assert.equal(snap.shortWindow.utilization, 0);
});

// ── Short window (Pro Searches) ─────────────────────────────

test('no cap → remaining-only "N Pro left" sublabel', () => {
  const snap = mapToSnapshot({ remaining_pro: 3 }, {}, NOW);
  assert.equal(snap.shortWindow.sublabelOverride, '3 Pro left');
  assert.equal(snap.shortWindow.utilization, 0);
});

// ── Long window (Deep Research) ─────────────────────────────

test('remaining_research present → longWindow with "Deep Research" label', () => {
  const snap = mapToSnapshot({ remaining_research: 2 }, { research: 4 }, NOW);
  assert.notEqual(snap.longWindow, null);
  assert.equal(snap.longWindow?.label, 'Deep Research');
  assert.equal(snap.longWindow?.sublabelOverride, '2 of 4 left');
  assert.equal(snap.longWindow?.utilization, 50);
});

test('remaining_research present without a cap → 0% and remaining-only', () => {
  const snap = mapToSnapshot({ remaining_research: 2 }, {}, NOW);
  assert.equal(snap.longWindow?.sublabelOverride, '2 left');
  assert.equal(snap.longWindow?.utilization, 0);
});

test('remaining_research absent → longWindow is null', () => {
  const snap = mapToSnapshot({ remaining_pro: 5 }, {}, NOW);
  assert.equal(snap.longWindow, null);
});

// ── Edge cases ──────────────────────────────────────────────

test('completely empty body → safe defaults, no throw', () => {
  const snap = mapToSnapshot({}, {}, NOW);
  assert.equal(snap.provider, 'perplexity');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, '0 Pro left');
  assert.equal(snap.longWindow, null);
});

test('resetsAt is now + 86400s (daily window)', () => {
  const snap = mapToSnapshot({ remaining_pro: 5 }, {}, NOW);
  const expected = new Date(NOW + DAY_SEC * 1000).toISOString();
  assert.equal(snap.shortWindow.resetsAt, expected);
});

test('windowDurationSec is 86400', () => {
  const snap = mapToSnapshot({}, {}, NOW);
  assert.equal(snap.shortWindow.windowDurationSec, DAY_SEC);
});

// ── Labs extras ─────────────────────────────────────────────

test('remaining_labs > 0 → extras.labsRemaining populated', () => {
  const snap = mapToSnapshot({ remaining_labs: 3 }, { labs: 6 }, NOW);
  assert.notEqual(snap.extras.labsRemaining, undefined);
  assert.equal(snap.extras.labsRemaining?.sublabelOverride, '3 of 6 left');
  assert.equal(snap.extras.labsRemaining?.label, 'Labs');
  assert.equal(snap.extras.labsRemaining?.utilization, 50);
});

test('remaining_labs = 0 → extras.labsRemaining not populated', () => {
  const snap = mapToSnapshot({ remaining_labs: 0 }, {}, NOW);
  assert.equal(snap.extras.labsRemaining, undefined);
});
