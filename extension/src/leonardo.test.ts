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

test('past tokenRenewalDate → falls back to now + 30d', () => {
  const pastDate = new Date(NOW - DAY_SEC * 1000).toISOString();
  const snap = mapToSnapshot({ tokenRenewalDate: pastDate }, NOW);
  const expected = new Date(NOW + 30 * DAY_SEC * 1000).toISOString();
  assert.equal(snap.shortWindow.resetsAt, expected);
});

test('missing tokenRenewalDate → falls back to now + 30d', () => {
  const snap = mapToSnapshot({}, NOW);
  const expected = new Date(NOW + 30 * DAY_SEC * 1000).toISOString();
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

test('windowDurationSec is 30 days (monthly allotments)', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.shortWindow.windowDurationSec, 30 * DAY_SEC);
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

// ── API key path (/api/rest/v1/me) ──────────────────────────

import { AuthError, fetchLeonardoUsageWithApiKey, mapMeToSnapshot } from './leonardo';
import { applyRenewal, trackRenewal } from './renewal';

function stubFetch(status: number, body: unknown = {}) {
  const calls: { url: string; headers: Record<string, string> }[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (url: string, init?: { headers?: Record<string, string> }) => {
    calls.push({ url, headers: init?.headers ?? {} });
    return { status, ok: status >= 200 && status < 300, json: async () => body };
  }) as unknown as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

test('/me mapping: subscription + paid tokens summed, utilization 0 (no plan to cap against)', () => {
  const renewal = new Date(NOW + 20 * DAY_SEC * 1000).toISOString();
  const snap = mapMeToSnapshot(
    { subscriptionTokens: 1200, paidTokens: 300, tokenRenewalDate: renewal },
    NOW,
  );
  assert.equal(snap.provider, 'leonardo');
  assert.equal(snap.shortWindow.sublabelOverride, '1500 tokens left');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.resetsAt, renewal);
  assert.equal(snap.shortWindow.windowDurationSec, 30 * DAY_SEC); // far renewal → monthly
  assert.equal(snap.estimated, false);
});

test('/me mapping: near renewal → daily window; null/missing fields → 0 tokens', () => {
  const soon = new Date(NOW + 3600 * 1000).toISOString();
  assert.equal(mapMeToSnapshot({ tokenRenewalDate: soon }, NOW).shortWindow.windowDurationSec, DAY_SEC);
  const empty = mapMeToSnapshot({ subscriptionTokens: null, paidTokens: null }, NOW);
  assert.equal(empty.shortWindow.sublabelOverride, '0 tokens left');
  assert.equal(mapMeToSnapshot(null, NOW).shortWindow.sublabelOverride, '0 tokens left');
});

test('api key: Bearer key against cloud.leonardo.ai /me, reads user_details[0]', async () => {
  const stub = stubFetch(200, { user_details: [{ subscriptionTokens: 50, paidTokens: 0 }] });
  try {
    const { snapshot: snap, balance, renewalKnown } = await fetchLeonardoUsageWithApiKey('leo_key');
    assert.equal(balance, 50);
    assert.equal(renewalKnown, false);
    assert.equal(stub.calls[0]?.url, 'https://cloud.leonardo.ai/api/rest/v1/me');
    assert.equal(stub.calls[0]?.headers['Authorization'], 'Bearer leo_key');
    assert.equal(snap.shortWindow.sublabelOverride, '50 tokens left');
  } finally {
    stub.restore();
  }
});

test('api key: 401 → AuthError with a key-specific message', async () => {
  const stub = stubFetch(401);
  try {
    await assert.rejects(
      fetchLeonardoUsageWithApiKey('bad'),
      (err: unknown) => err instanceof AuthError && /API key/.test(err.message),
    );
  } finally {
    stub.restore();
  }
});

// ── Learning the monthly cycle from the refill ──────────────

const T0 = Date.UTC(2026, 10, 9, 12, 0, 0); // 2026-11-09
const HOUR = 3600 * 1000;

test('renewal: no refill seen yet → snapshot unchanged, no reset in sublabel', () => {
  const state = trackRenewal(null, 150, 0, T0);
  assert.equal(state.anchorMs, null);
  const snap = mapMeToSnapshot({ subscriptionTokens: 150, paidTokens: 0 }, T0);
  const out = applyRenewal({ snapshot: snap, balance: 150, purchased: 0, renewalKnown: false }, state, T0);
  assert.equal(out.shortWindow.sublabelOverride, '150 tokens left');
});

test('renewal: spending lowers the balance → still no anchor', () => {
  let s = trackRenewal(null, 150, 0, T0);
  s = trackRenewal(s, 90, 0, T0 + HOUR);
  assert.equal(s.anchorMs, null);
});

test('renewal: balance jumps up with paid unchanged → anchored; reset one month later', () => {
  let s = trackRenewal(null, 20, 0, T0 - HOUR);
  s = trackRenewal(s, 150, 0, T0);
  assert.equal(s.anchorMs, T0);
  const now = T0 + 7 * 24 * HOUR; // Nov 16
  const snap = mapMeToSnapshot({ subscriptionTokens: 120, paidTokens: 0 }, now);
  const out = applyRenewal({ snapshot: snap, balance: 120, purchased: 0, renewalKnown: false }, s, now);
  assert.equal(out.shortWindow.resetsAt, '2026-12-09T12:00:00.000Z');
  assert.equal(out.shortWindow.sublabelOverride, '120 tokens left · resets in 23d');
  assert.equal(out.shortWindow.windowDurationSec, 30 * 24 * 3600);
});

test('renewal: a token purchase is not a refill', () => {
  let s = trackRenewal(null, 20, 0, T0 - HOUR);
  s = trackRenewal(s, 20, 500, T0);
  assert.equal(s.anchorMs, null);
});

test('renewal: refill seen after a long gap (browser closed) is not trusted', () => {
  let s = trackRenewal(null, 20, 0, T0 - 5 * 24 * HOUR);
  s = trackRenewal(s, 150, 0, T0);
  assert.equal(s.anchorMs, null);
});

test('renewal: a real renewal date from the API wins over the learned one', () => {
  let s = trackRenewal(null, 20, 0, T0 - HOUR);
  s = trackRenewal(s, 150, 0, T0);
  const snap = mapMeToSnapshot({ subscriptionTokens: 150, paidTokens: 0 }, T0);
  const out = applyRenewal({ snapshot: snap, balance: 150, purchased: 0, renewalKnown: true }, s, T0);
  assert.equal(out, snap);
});
