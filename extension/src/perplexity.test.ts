/**
 * Unit tests for the Perplexity rate-limit parser.
 *
 * All tests exercise `mapToSnapshot` directly.
 *
 * Real API response (free account, 2026-06-01):
 *   { "free_queries": { "available": true, "remaining_detail": { "kind": "not_provided" } },
 *     "remaining_agentic_research": 0, "remaining_labs": 0, "remaining_pro": 5,
 *     "remaining_research": 0, "model_specific_limits": {}, "sources": { ... } }
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mapToSnapshot } from './perplexity';

// Fixed "now" so resetsAt assertions are deterministic.
// 2026-06-01T00:00:00.000Z
const NOW = 1_748_736_000_000;
const DAY_SEC = 86400;

// ── Real fixture (free account) ────────────────────────────

test('real fixture: 5 pro remaining, 0 research/labs → correct sublabels', () => {
  const snap = mapToSnapshot(
    {
      remaining_pro: 5,
      remaining_research: 0,
      remaining_labs: 0,
      remaining_agentic_research: 0,
    },
    NOW,
  );
  assert.equal(snap.provider, 'perplexity');
  assert.equal(snap.shortWindow.label, 'Pro Searches');
  assert.equal(snap.shortWindow.utilization, 0); // no total → always 0
  assert.equal(snap.shortWindow.sublabelOverride, '5 Pro left');
  assert.equal(snap.planLabel, 'Perplexity');
  assert.equal(snap.capturedAt, NOW);
  assert.equal(snap.estimated, false);
});

// ── Short window (Pro Searches) ─────────────────────────────

test('shortWindow.sublabelOverride shows remaining_pro count', () => {
  const snap = mapToSnapshot({ remaining_pro: 3 }, NOW);
  assert.equal(snap.shortWindow.sublabelOverride, '3 Pro left');
});

test('remaining_pro = 0 → "0 Pro left"', () => {
  const snap = mapToSnapshot({ remaining_pro: 0 }, NOW);
  assert.equal(snap.shortWindow.sublabelOverride, '0 Pro left');
});

// ── Long window (Deep Research) ─────────────────────────────

test('remaining_research present → longWindow with "Deep Research" label', () => {
  const snap = mapToSnapshot({ remaining_research: 2 }, NOW);
  assert.notEqual(snap.longWindow, null);
  assert.equal(snap.longWindow?.label, 'Deep Research');
  assert.equal(snap.longWindow?.sublabelOverride, '2 left');
  assert.equal(snap.longWindow?.utilization, 0);
});

test('remaining_research = 0 → longWindow still included (field is present)', () => {
  // The field is explicitly present even if zero — show the bar.
  const snap = mapToSnapshot({ remaining_research: 0 }, NOW);
  assert.notEqual(snap.longWindow, null);
  assert.equal(snap.longWindow?.sublabelOverride, '0 left');
});

test('remaining_research absent → longWindow is null', () => {
  const snap = mapToSnapshot({ remaining_pro: 5 }, NOW);
  assert.equal(snap.longWindow, null);
});

// ── Edge cases ──────────────────────────────────────────────

test('completely empty body → safe defaults, no throw', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.provider, 'perplexity');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, '0 Pro left');
  assert.equal(snap.longWindow, null);
});

test('resetsAt is now + 86400s (daily window)', () => {
  const snap = mapToSnapshot({ remaining_pro: 5 }, NOW);
  const expected = new Date(NOW + DAY_SEC * 1000).toISOString();
  assert.equal(snap.shortWindow.resetsAt, expected);
});

test('windowDurationSec is 86400', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.shortWindow.windowDurationSec, DAY_SEC);
});

// ── Labs extras ─────────────────────────────────────────────

test('remaining_labs > 0 → extras.labsRemaining populated', () => {
  const snap = mapToSnapshot({ remaining_labs: 3 }, NOW);
  assert.notEqual(snap.extras.labsRemaining, undefined);
  assert.equal(snap.extras.labsRemaining?.sublabelOverride, '3 left');
  assert.equal(snap.extras.labsRemaining?.label, 'Labs');
});

test('remaining_labs = 0 → extras.labsRemaining not populated', () => {
  const snap = mapToSnapshot({ remaining_labs: 0 }, NOW);
  assert.equal(snap.extras.labsRemaining, undefined);
});
