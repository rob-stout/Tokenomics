/**
 * Unit tests for the ElevenLabs subscription parser.
 *
 * All tests exercise `mapToSnapshot` directly — the pure mapper is the only
 * logic worth testing; the fetch layer is tested end-to-end by a human capture.
 *
 * Auth has been corrected to Firebase Bearer token (api.us.elevenlabs.io).
 * The mapper is unchanged — character_count/character_limit → utilization%,
 * next_character_count_reset_unix → resetsAt. A past reset timestamp now falls
 * back to now + 30d instead of showing a negative countdown.
 *
 * Real response (confirmed 2026-06-01):
 *   { "tier": "free", "character_count": 0, "character_limit": 10000,
 *     "next_character_count_reset_unix": 1777606325, "status": "free" }
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mapToSnapshot } from './elevenlabs';

// Fixed "now" so reset-time assertions are deterministic.
// 2026-06-02T00:00:00.000Z
const NOW = 1_748_822_400_000;
const THIRTY_DAY_SEC = 30 * 24 * 3600;

// ── Full usage (near the monthly cap) ───────────────────────

test('Creator plan, 90% used → 90% utilization, correct planLabel', () => {
  const snap = mapToSnapshot(
    {
      character_count: 90_000,
      character_limit: 100_000,
      next_character_count_reset_unix: Math.floor(NOW / 1000) + THIRTY_DAY_SEC,
      tier: 'creator',
    },
    NOW,
  );
  assert.equal(snap.provider, 'elevenlabs');
  assert.equal(snap.planLabel, 'Creator');
  assert.equal(snap.shortWindow.utilization, 90);
  assert.equal(snap.shortWindow.label, 'Characters');
  assert.equal(snap.longWindow, null);
  assert.equal(snap.estimated, false);
});

// ── Near-limit (>100% clamped to 100) ───────────────────────

test('utilization clamps to 100 when usage exceeds limit', () => {
  const snap = mapToSnapshot(
    {
      character_count: 200_000,
      character_limit: 100_000,
      next_character_count_reset_unix: Math.floor(NOW / 1000) + THIRTY_DAY_SEC,
      tier: 'pro',
    },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 100);
  assert.equal(snap.planLabel, 'Pro');
});

// ── Fresh / zero usage ───────────────────────────────────────

test('free plan, 0 characters used → 0% utilization', () => {
  const snap = mapToSnapshot(
    {
      character_count: 0,
      character_limit: 10_000,
      next_character_count_reset_unix: Math.floor(NOW / 1000) + THIRTY_DAY_SEC,
      tier: 'free',
    },
    NOW,
  );
  assert.equal(snap.planLabel, 'Free');
  assert.equal(snap.shortWindow.utilization, 0);
});

// ── Missing / undefined fields ───────────────────────────────

test('completely empty body → safe defaults, no throw', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.provider, 'elevenlabs');
  assert.equal(snap.planLabel, 'ElevenLabs');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.longWindow, null);
  assert.equal(snap.estimated, false);
});

test('missing character_limit → 0% utilization (no divide-by-zero)', () => {
  const snap = mapToSnapshot(
    { character_count: 5_000, tier: 'starter' },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.planLabel, 'Starter');
});

test('missing next_character_count_reset_unix → fallback to now + 30d', () => {
  const snap = mapToSnapshot(
    { character_count: 0, character_limit: 10_000, tier: 'free' },
    NOW,
  );
  const expectedResetsAt = new Date(NOW + THIRTY_DAY_SEC * 1000).toISOString();
  assert.equal(snap.shortWindow.resetsAt, expectedResetsAt);
});

// ── resetsAt is correctly derived from epoch seconds ─────────

test('resetsAt ISO string matches next_character_count_reset_unix', () => {
  const resetSec = Math.floor(NOW / 1000) + THIRTY_DAY_SEC;
  const snap = mapToSnapshot(
    {
      character_count: 1_000,
      character_limit: 100_000,
      next_character_count_reset_unix: resetSec,
      tier: 'scale',
    },
    NOW,
  );
  assert.equal(snap.shortWindow.resetsAt, new Date(resetSec * 1000).toISOString());
  assert.equal(snap.planLabel, 'Scale');
});

// ── Tier label mapping ───────────────────────────────────────

test('tier "business" maps to "Business"', () => {
  const snap = mapToSnapshot({ tier: 'business' }, NOW);
  assert.equal(snap.planLabel, 'Business');
});

test('unknown tier is title-cased', () => {
  const snap = mapToSnapshot({ tier: 'enterprise_xyz' }, NOW);
  assert.equal(snap.planLabel, 'Enterprise_xyz');
});

test('empty tier string falls back to "ElevenLabs"', () => {
  const snap = mapToSnapshot({ tier: '' }, NOW);
  assert.equal(snap.planLabel, 'ElevenLabs');
});

// ── Numeric string coercion ───────────────────────────────────

test('character_count as string is coerced to number', () => {
  const snap = mapToSnapshot(
    {
      character_count: '25000' as unknown as number,
      character_limit: 100_000,
      tier: 'creator',
    },
    NOW,
  );
  // 25_000 / 100_000 = 25%
  assert.equal(snap.shortWindow.utilization, 25);
});

// ── capturedAt is passed through ─────────────────────────────

test('capturedAt matches the `now` parameter', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.capturedAt, NOW);
});

// ── windowDurationSec is 30 days ─────────────────────────────

test('shortWindow.windowDurationSec is 30 days', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.shortWindow.windowDurationSec, THIRTY_DAY_SEC);
});

// ── Past reset timestamp ─────────────────────────────────────

test('past next_character_count_reset_unix → falls back to now + 30d', () => {
  // Epoch 1 is 1970-01-01 — well in the past.
  const snap = mapToSnapshot(
    { character_count: 1000, character_limit: 10_000, next_character_count_reset_unix: 1 },
    NOW,
  );
  // A past timestamp is treated as now + 30d (not a negative countdown).
  const expectedResetsAt = new Date(NOW + THIRTY_DAY_SEC * 1000).toISOString();
  assert.equal(snap.shortWindow.resetsAt, expectedResetsAt);
});

// ── Confirmed real response fields ───────────────────────────

test('real fixture: free plan, 0/10000 characters, future reset', () => {
  // next_character_count_reset_unix: 1777606325 (far future — 2026+)
  const resetSec = 1_777_606_325;
  const snap = mapToSnapshot(
    {
      tier: 'free',
      character_count: 0,
      character_limit: 10_000,
      next_character_count_reset_unix: resetSec,
    },
    NOW,
  );
  assert.equal(snap.planLabel, 'Free');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.resetsAt, new Date(resetSec * 1000).toISOString());
});
