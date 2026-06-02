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
  assert.equal(snap.shortWindow.utilization, 0); // no total → always 0
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
