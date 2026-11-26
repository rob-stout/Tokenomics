/**
 * Unit tests for the Suno billing parser, against a REAL capture of
 * GET https://studio-api.prod.suno.com/api/billing/info/ (Free account,
 * 2026-11-23, ids redacted): fixtures/suno-billing-info.json.
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mapToSnapshot, pickBilling, readSessionToken, toRenewalPoll } from './suno';
import { applyRenewal, trackRenewal } from './renewal';
import REAL from './fixtures/suno-billing-info.json';

const NOW = Date.UTC(2026, 10, 23, 16, 0, 0);
const HOUR = 3600 * 1000;
const DAY_MS = 24 * HOUR;

// ── pickBilling ─────────────────────────────────────────────

test('real capture: keeps only display fields; plans[] catalogue is ignored', () => {
  const picked = pickBilling(REAL);
  assert.deepEqual(picked, {
    totalCreditsLeft: 300,
    monthlyLimit: 300,
    monthlyUsage: 0,
    credits: 0,
    isActive: false,
  });
  // subscription_type:false and the plan catalogue must not leak through.
  const json = JSON.stringify(picked);
  assert.equal(json.includes('Free Plan'), false);
  assert.equal(json.includes('credit_rate_limit'), false);
});

test('pickBilling keeps subscription_type only when it is a string', () => {
  assert.equal(pickBilling({ subscription_type: 'pro' }).subscriptionType, 'pro');
  assert.equal(pickBilling({ subscription_type: false }).subscriptionType, undefined);
});

test('pickBilling tolerates garbage input', () => {
  assert.deepEqual(pickBilling(null), {});
  assert.deepEqual(pickBilling('nope'), {});
  assert.deepEqual(pickBilling([1, 2]), {});
  assert.deepEqual(pickBilling({ total_credits_left: 'abc', is_active: 'yes' }), {});
});

test('pickBilling accepts numeric strings', () => {
  assert.equal(pickBilling({ monthly_limit: '300' }).monthlyLimit, 300);
});

// ── mapToSnapshot ───────────────────────────────────────────

test('real capture: 0 of 300 used → 0%, "300 credits left", Free', () => {
  const snap = mapToSnapshot(pickBilling(REAL), NOW);
  assert.equal(snap.provider, 'suno');
  assert.equal(snap.shortWindow.label, 'Credits');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, '300 credits left');
  assert.equal(snap.shortWindow.windowDurationSec, 30 * 86400);
  assert.equal(snap.planLabel, 'Free');
  assert.equal(snap.longWindow, null);
  assert.equal(snap.estimated, false);
});

test('no reset date from the API → placeholder now + 30d (never empty: the bridge needs a date)', () => {
  const snap = mapToSnapshot(pickBilling(REAL), NOW);
  assert.equal(snap.shortWindow.resetsAt, new Date(NOW + 30 * DAY_MS).toISOString());
});

test('spent credits: 60 of 300 used → 20%', () => {
  const snap = mapToSnapshot(
    pickBilling({ ...REAL, monthly_usage: 60, total_credits_left: 240 }),
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 20);
  assert.equal(snap.shortWindow.sublabelOverride, '240 credits left');
});

test('usage derived from limit - left when monthly_usage missing', () => {
  const snap = mapToSnapshot({ totalCreditsLeft: 500, monthlyLimit: 2000 }, NOW);
  assert.equal(snap.shortWindow.utilization, 75);
});

test('credits above the monthly limit (top-ups) clamp utilization at 0', () => {
  const snap = mapToSnapshot({ totalCreditsLeft: 4000, monthlyLimit: 2500 }, NOW);
  assert.equal(snap.shortWindow.utilization, 0);
});

test('usage over limit clamps at 100', () => {
  const snap = mapToSnapshot({ monthlyUsage: 3000, monthlyLimit: 2500 }, NOW);
  assert.equal(snap.shortWindow.utilization, 100);
});

test('empty billing → 0%, no sublabel, generic plan label', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, undefined);
  assert.equal(snap.planLabel, 'Suno');
});

test('zero limit does not divide by zero', () => {
  assert.equal(mapToSnapshot({ monthlyLimit: 0, monthlyUsage: 10 }, NOW).shortWindow.utilization, 0);
});

// ── plan label ──────────────────────────────────────────────

test('plan label: active subscriber with string type → capitalised type', () => {
  assert.equal(mapToSnapshot({ isActive: true, subscriptionType: 'pro' }, NOW).planLabel, 'Pro');
});

test('plan label: active but no type string → "Suno"', () => {
  assert.equal(mapToSnapshot({ isActive: true }, NOW).planLabel, 'Suno');
});

test('plan label: is_active false wins over a leftover type string → Free', () => {
  assert.equal(mapToSnapshot({ isActive: false, subscriptionType: 'pro' }, NOW).planLabel, 'Free');
});

// ── session cookie ──────────────────────────────────────────

const JWT = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyXzEifQ.c2lnbmF0dXJl';

test('readSessionToken: finds __session among other cookies', () => {
  assert.equal(readSessionToken(`a=1; __session=${JWT}; b=2`), JWT);
});

test('readSessionToken: ignores lookalike names and non-JWT values', () => {
  assert.equal(readSessionToken(`x__session=${JWT}`), null);
  assert.equal(readSessionToken('__session=abc'), null);
  assert.equal(readSessionToken('__session='), null);
  assert.equal(readSessionToken(''), null);
});

// ── learning the reset from the refill ──────────────────────

test('renewal poll: balance = total_credits_left, purchased = credits, no known date', () => {
  const poll = toRenewalPoll(pickBilling(REAL), NOW);
  assert.ok(poll);
  assert.equal(poll.balance, 300);
  assert.equal(poll.purchased, 0);
  assert.equal(poll.renewalKnown, false);
  assert.equal(toRenewalPoll({}, NOW), null);
});

test('renewal: spending then a refill → "240 credits left · resets in 12d" style countdown', () => {
  const t0 = Date.UTC(2026, 10, 11, 12, 0, 0);
  const spent = toRenewalPoll(pickBilling({ ...REAL, total_credits_left: 20, monthly_usage: 280 }), t0 - HOUR);
  assert.ok(spent);
  let s = trackRenewal(null, spent.balance, spent.purchased, t0 - HOUR);
  const refilled = toRenewalPoll(pickBilling(REAL), t0);
  assert.ok(refilled);
  s = trackRenewal(s, refilled.balance, refilled.purchased, t0);
  assert.equal(s.anchorMs, t0);

  const now = t0 + 18 * DAY_MS; // Nov 29
  const later = toRenewalPoll(pickBilling({ ...REAL, total_credits_left: 240, monthly_usage: 60 }), now);
  assert.ok(later);
  const out = applyRenewal(later, s, now);
  assert.equal(out.shortWindow.resetsAt, '2026-12-11T12:00:00.000Z');
  assert.equal(out.shortWindow.sublabelOverride, '240 credits left · resets in 12d');
});

test('renewal: buying credits (purchased goes up) is not a refill', () => {
  let s = trackRenewal(null, 20, 0, NOW - HOUR);
  s = trackRenewal(s, 520, 500, NOW);
  assert.equal(s.anchorMs, null);
});

test('renewal: a paid user at 0 who gets the 50 daily top-up is NOT anchored', () => {
  let s = trackRenewal(null, 0, 0, NOW - HOUR, 50);
  s = trackRenewal(s, 50, 0, NOW, 50);
  assert.equal(s.anchorMs, null);
});

test('renewal: a refill bigger than the 50 daily amount still anchors', () => {
  let s = trackRenewal(null, 0, 0, NOW - HOUR, 50);
  s = trackRenewal(s, 2500, 0, NOW, 50);
  assert.equal(s.anchorMs, NOW);
});
