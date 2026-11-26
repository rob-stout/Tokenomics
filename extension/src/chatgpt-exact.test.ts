/**
 * Unit tests for the EXACT ChatGPT reader's pure mapper (`mapWhamUsageToSnapshot`).
 *
 * The fetch layer (token grab + /wham/usage) is covered by live verification;
 * the mapper is the logic worth pinning. The `free` fixture is the REAL shape
 * captured from a logged-in session; the `plus` fixture is the expected
 * two-window shape (5-hour primary + weekly secondary).
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mapWhamUsageToSnapshot, type WhamUsageResponse } from './chatgpt';

// Fixed "now" so any reset math is deterministic. 2026-06-01T00:00:00.000Z
const NOW = 1_748_736_000_000;

// ── Real fixture: free account, single 30-day window ──────────
test('free: exact, not estimated; monthly primary; no long window', () => {
  const data: WhamUsageResponse = {
    plan_type: 'free',
    rate_limit: {
      primary_window: { used_percent: 5, limit_window_seconds: 2592000, reset_at: 1783102293 },
      secondary_window: null,
    },
  };
  const snap = mapWhamUsageToSnapshot(data, NOW);
  assert.ok(snap, 'should map');
  assert.equal(snap!.provider, 'chatgpt'); // NOT 'codex' — its own pool
  assert.equal(snap!.estimated, false); // exact!
  assert.equal(snap!.planLabel, 'Free');
  assert.equal(snap!.shortWindow.utilization, 5);
  assert.equal(snap!.shortWindow.label, 'Monthly');
  assert.equal(snap!.shortWindow.windowDurationSec, 2592000);
  assert.equal(snap!.shortWindow.resetsAt, new Date(1783102293 * 1000).toISOString());
  assert.equal(snap!.longWindow, null);
});

// ── Plus: 5-hour primary + weekly secondary ───────────────────
test('plus: two windows mapped (5-hour + weekly)', () => {
  const data: WhamUsageResponse = {
    plan_type: 'chatgpt_plus',
    rate_limit: {
      primary_window: { used_percent: 42, limit_window_seconds: 18000, reset_at: 1748750400 },
      secondary_window: { used_percent: 12, limit_window_seconds: 604800, reset_at: 1749340800 },
    },
  };
  const snap = mapWhamUsageToSnapshot(data, NOW);
  assert.ok(snap);
  assert.equal(snap!.estimated, false);
  assert.equal(snap!.planLabel, 'Plus');
  assert.equal(snap!.shortWindow.utilization, 42);
  assert.equal(snap!.shortWindow.label, '5-Hour Window');
  assert.equal(snap!.longWindow?.utilization, 12);
  assert.equal(snap!.longWindow?.label, 'Weekly');
});

// ── reset_after_seconds fallback (no absolute reset_at) ───────
test('uses reset_after_seconds when reset_at is absent', () => {
  const data: WhamUsageResponse = {
    plan_type: 'plus',
    rate_limit: {
      primary_window: { used_percent: 50, limit_window_seconds: 10800, reset_after_seconds: 3600 },
      secondary_window: null,
    },
  };
  const snap = mapWhamUsageToSnapshot(data, NOW);
  assert.ok(snap);
  assert.equal(snap!.shortWindow.resetsAt, new Date(NOW + 3600 * 1000).toISOString());
  assert.equal(snap!.shortWindow.label, '3-Hour Window');
});

// ── Malformed → null so the caller falls back to the counter ──
test('missing primary window → null (caller falls back)', () => {
  assert.equal(mapWhamUsageToSnapshot({ rate_limit: { primary_window: null } }, NOW), null);
  assert.equal(mapWhamUsageToSnapshot({}, NOW), null);
  assert.equal(
    mapWhamUsageToSnapshot({ rate_limit: { primary_window: { limit_window_seconds: 100 } } }, NOW),
    null,
  );
});

// ── Clamping ──────────────────────────────────────────────────
test('utilization is clamped to 0–100 and rounded', () => {
  const over = mapWhamUsageToSnapshot(
    { plan_type: 'free', rate_limit: { primary_window: { used_percent: 130.6, limit_window_seconds: 2592000 } } },
    NOW,
  );
  assert.equal(over!.shortWindow.utilization, 100);
});

// ── Window classification by length, not slot ─────────────────
test('weekly primary + 5-hour secondary: sorted by length, not slot', () => {
  const data: WhamUsageResponse = {
    plan_type: 'pro',
    rate_limit: {
      primary_window: { used_percent: 30, limit_window_seconds: 604800, reset_at: 1749340800 },
      secondary_window: { used_percent: 8, limit_window_seconds: 18000, reset_at: 1748750400 },
    },
  };
  const snap = mapWhamUsageToSnapshot(data, NOW);
  assert.ok(snap);
  assert.equal(snap!.shortWindow.label, '5-Hour Window');
  assert.equal(snap!.shortWindow.utilization, 8);
  assert.equal(snap!.longWindow?.label, 'Weekly');
  assert.equal(snap!.longWindow?.utilization, 30);
});

test('a lone weekly window is the short window, labelled Weekly', () => {
  const snap = mapWhamUsageToSnapshot(
    { plan_type: 'plus', rate_limit: { primary_window: { used_percent: 10, limit_window_seconds: 604800, reset_at: 1749340800 } } },
    NOW,
  );
  assert.equal(snap!.shortWindow.label, 'Weekly');
  assert.equal(snap!.longWindow, null);
});

test('windows are marked as the Codex allowance', () => {
  const snap = mapWhamUsageToSnapshot(
    { plan_type: 'plus', rate_limit: { primary_window: { used_percent: 10, limit_window_seconds: 18000, reset_at: 1748750400 } } },
    NOW,
  );
  assert.match(snap!.shortWindow.sublabelOverride ?? '', /^Codex allowance · resets in/);
});

test('a ~6h session window is labelled in hours', () => {
  const snap = mapWhamUsageToSnapshot(
    { plan_type: 'plus', rate_limit: { primary_window: { used_percent: 1, limit_window_seconds: 21600, reset_at: 1748750400 } } },
    NOW,
  );
  assert.equal(snap!.shortWindow.label, '6-Hour Window');
});

// ── Plan label from plan_type ─────────────────────────────────
test('plan_type → label table', () => {
  const cases: Array<[string, string]> = [
    ['free', 'Free'],
    ['go', 'Go'],
    ['plus', 'Plus'],
    ['prolite', 'Pro 100'],
    ['pro', 'Pro 200'],
    ['promax', 'Pro 500'],
    ['team', 'Team'],
    ['business', 'Business'],
    ['self_serve_business_usage_based', 'Business'],
    ['enterprise', 'Enterprise'],
    ['enterprise_cbp_usage_based', 'Enterprise'],
    ['edu', 'Edu'],
    ['education', 'Edu'],
    ['something_new', ''],
  ];
  for (const [planType, label] of cases) {
    const snap = mapWhamUsageToSnapshot(
      { plan_type: planType, rate_limit: { primary_window: { used_percent: 1, limit_window_seconds: 18000, reset_at: 1748750400 } } },
      NOW,
    );
    assert.equal(snap!.planLabel, label, planType);
  }
});
