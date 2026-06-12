/**
 * Unit tests for the Leonardo usage parser.
 *
 * All tests exercise `mapToSnapshot` directly.
 *
 * Real API response (Free plan, 2026-06-01):
 *   { "plan": "FREE", "subscriptionTokens": 150, "paidTokens": 0,
 *     "rolloverTokens": 0, "tokenRenewalDate": "..." }
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mapToSnapshot } from './leonardo';

// Fixed "now" so resetsAt assertions are deterministic.
// 2026-06-01T00:00:00.000Z
const NOW = 1_748_736_000_000;
const DAY_SEC = 86400;

// ── Real fixture (Free plan) ───────────────────────────────

test('real fixture: FREE plan, 150 subscription tokens → correct sublabel', () => {
  const renewalDate = new Date(NOW + DAY_SEC * 1000).toISOString();
  const snap = mapToSnapshot(
    {
      plan: 'FREE',
      subscriptionTokens: 150,
      paidTokens: 0,
      rolloverTokens: 0,
      tokenRenewalDate: renewalDate,
    },
    NOW,
  );
  assert.equal(snap.provider, 'leonardo');
  assert.equal(snap.shortWindow.label, 'Tokens');
  assert.equal(snap.shortWindow.utilization, 0); // full balance → 0% used
  assert.equal(snap.shortWindow.sublabelOverride, '150 tokens left');
  assert.equal(snap.planLabel, 'Free');
  assert.equal(snap.longWindow, null);
  assert.equal(snap.estimated, false);
  assert.equal(snap.capturedAt, NOW);
});

// ── Token aggregation ────────────────────────────────────────

test('totalLeft = subscriptionTokens + paidTokens + rolloverTokens', () => {
  const snap = mapToSnapshot(
    { subscriptionTokens: 100, paidTokens: 50, rolloverTokens: 25 },
    NOW,
  );
  assert.equal(snap.shortWindow.sublabelOverride, '175 tokens left');
});

test('all zeroes → "0 tokens left"', () => {
  const snap = mapToSnapshot(
    { subscriptionTokens: 0, paidTokens: 0, rolloverTokens: 0 },
    NOW,
  );
  assert.equal(snap.shortWindow.sublabelOverride, '0 tokens left');
});

// ── Plan label mapping ───────────────────────────────────────

test('plan FREE → "Free"', () => {
  const snap = mapToSnapshot({ plan: 'FREE' }, NOW);
  assert.equal(snap.planLabel, 'Free');
});

test('plan APPRENTICE_V2 → "Apprentice"', () => {
  const snap = mapToSnapshot({ plan: 'APPRENTICE_V2' }, NOW);
  assert.equal(snap.planLabel, 'Apprentice');
});

test('plan ARTISAN → "Artisan"', () => {
  const snap = mapToSnapshot({ plan: 'ARTISAN' }, NOW);
  assert.equal(snap.planLabel, 'Artisan');
});

test('plan MAESTRO_V2 → "Maestro"', () => {
  const snap = mapToSnapshot({ plan: 'MAESTRO_V2' }, NOW);
  assert.equal(snap.planLabel, 'Maestro');
});

test('unknown plan → first segment title-cased', () => {
  const snap = mapToSnapshot({ plan: 'ENTERPRISE_XYZ' }, NOW);
  assert.equal(snap.planLabel, 'Enterprise');
});

test('empty plan string → "Leonardo"', () => {
  const snap = mapToSnapshot({ plan: '' }, NOW);
  assert.equal(snap.planLabel, 'Leonardo');
});

// ── resetsAt from tokenRenewalDate ───────────────────────────

test('valid future tokenRenewalDate → used as resetsAt', () => {
  const futureDate = new Date(NOW + 2 * DAY_SEC * 1000).toISOString();
  const snap = mapToSnapshot({ tokenRenewalDate: futureDate }, NOW);
  assert.equal(snap.shortWindow.resetsAt, futureDate);
});

test('past tokenRenewalDate → falls back to now + 24h', () => {
  const pastDate = new Date(NOW - DAY_SEC * 1000).toISOString();
  const snap = mapToSnapshot({ tokenRenewalDate: pastDate }, NOW);
  const expected = new Date(NOW + DAY_SEC * 1000).toISOString();
  assert.equal(snap.shortWindow.resetsAt, expected);
});

test('missing tokenRenewalDate → falls back to now + 24h', () => {
  const snap = mapToSnapshot({}, NOW);
  const expected = new Date(NOW + DAY_SEC * 1000).toISOString();
  assert.equal(snap.shortWindow.resetsAt, expected);
});

// ── Null / missing input ─────────────────────────────────────

test('null details → safe defaults, no throw', () => {
  const snap = mapToSnapshot(null, NOW);
  assert.equal(snap.provider, 'leonardo');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, '0 tokens left');
  assert.equal(snap.planLabel, 'Leonardo');
  assert.equal(snap.longWindow, null);
});

test('empty object → safe defaults', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.shortWindow.sublabelOverride, '0 tokens left');
});

// ── windowDurationSec ────────────────────────────────────────

test('windowDurationSec is 86400 (daily)', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.shortWindow.windowDurationSec, DAY_SEC);
});

// ── Utilization cap table ────────────────────────────────────

test('FREE, subscriptionTokens 102 → utilization 32 and sublabel "102 tokens left"', () => {
  // round((150 - 102) / 150 * 100) = round(32) = 32
  const snap = mapToSnapshot({ plan: 'FREE', subscriptionTokens: 102, paidTokens: 0, rolloverTokens: 0 }, NOW);
  assert.equal(snap.shortWindow.utilization, 32);
  assert.equal(snap.shortWindow.sublabelOverride, '102 tokens left');
});

test('FREE, subscriptionTokens 75 → utilization 50', () => {
  // round((150 - 75) / 150 * 100) = round(50) = 50
  const snap = mapToSnapshot({ plan: 'FREE', subscriptionTokens: 75, paidTokens: 0, rolloverTokens: 0 }, NOW);
  assert.equal(snap.shortWindow.utilization, 50);
});

test('ARTISAN, subscriptionTokens 12500 → utilization 50', () => {
  // round((25000 - 12500) / 25000 * 100) = round(50) = 50
  const snap = mapToSnapshot({ plan: 'ARTISAN', subscriptionTokens: 12500, paidTokens: 0, rolloverTokens: 0 }, NOW);
  assert.equal(snap.shortWindow.utilization, 50);
});

test('APPRENTICE_V2 strips suffix → cap 8500, subscriptionTokens 4250 → utilization 50', () => {
  // round((8500 - 4250) / 8500 * 100) = round(50) = 50
  const snap = mapToSnapshot({ plan: 'APPRENTICE_V2', subscriptionTokens: 4250, paidTokens: 0, rolloverTokens: 0 }, NOW);
  assert.equal(snap.shortWindow.utilization, 50);
});

test('unknown plan ENTERPRISE_XYZ → cap unknown → utilization 0 (safe fallback)', () => {
  const snap = mapToSnapshot({ plan: 'ENTERPRISE_XYZ', subscriptionTokens: 50, paidTokens: 0, rolloverTokens: 0 }, NOW);
  assert.equal(snap.shortWindow.utilization, 0);
});

test('clamp: FREE with subscriptionTokens 150 + paidTokens 100 (totalLeft 250 > cap 150) → utilization 0, not negative', () => {
  // (150 - 250) / 150 = -0.666... → clamp to 0
  const snap = mapToSnapshot({ plan: 'FREE', subscriptionTokens: 150, paidTokens: 100, rolloverTokens: 0 }, NOW);
  assert.equal(snap.shortWindow.utilization, 0);
});
