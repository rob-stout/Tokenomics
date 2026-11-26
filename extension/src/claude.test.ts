/**
 * Claude reader: org selection, plan label, limits[] parsing, usage credits.
 * Fixtures mirror the live captures of 2026-11-25 (Max 5x account, 2 orgs).
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mapToSnapshot, pickChatOrg, planFromOrg } from './claude-map';

const NOW = 1_795_000_000_000;

const chatOrg = {
  uuid: 'chat-org',
  capabilities: ['chat', 'claude_max'],
  rate_limit_tier: 'default_claude_max_5x',
  analytics_subscription_plan: 'claude_max 5x',
};
const apiOrg = {
  uuid: 'api-org',
  capabilities: ['api', 'api_individual', 'customer_terms:standard'],
  rate_limit_tier: 'auto_api_evaluation',
  analytics_subscription_plan: 'api_individual',
};

// ── Org selection ───────────────────────────────────────────

test('pickChatOrg skips an API org listed first', () => {
  assert.equal(pickChatOrg([apiOrg, chatOrg])?.uuid, 'chat-org');
});

test('pickChatOrg returns null when only API orgs exist', () => {
  assert.equal(pickChatOrg([apiOrg]), null);
  assert.equal(pickChatOrg([]), null);
  assert.equal(pickChatOrg({}), null);
});

test('pickChatOrg accepts claude_pro-only capabilities', () => {
  assert.equal(pickChatOrg([{ uuid: 'p', capabilities: ['claude_pro'] }])?.uuid, 'p');
});

// ── Plan label ──────────────────────────────────────────────

test('planFromOrg maps tiers', () => {
  assert.equal(planFromOrg(chatOrg), 'Max');
  assert.equal(planFromOrg({ rate_limit_tier: 'default_claude_max_20x' }), 'Ultra');
  assert.equal(planFromOrg({ rate_limit_tier: 'default_claude_ultra' }), 'Ultra');
  assert.equal(
    planFromOrg({ capabilities: ['chat', 'claude_pro'], rate_limit_tier: 'default_claude_ai' }),
    'Pro',
  );
});

test('planFromOrg falls back to capabilities / analytics plan', () => {
  assert.equal(planFromOrg({ capabilities: ['chat', 'claude_max'] }), 'Max');
  assert.equal(
    planFromOrg({ capabilities: ['chat', 'claude_max'], analytics_subscription_plan: 'claude_max 20x' }),
    'Ultra',
  );
});

test('planFromOrg omits unknown / free plans', () => {
  assert.equal(planFromOrg({ capabilities: ['chat'], rate_limit_tier: 'default_claude_ai' }), '');
  assert.equal(planFromOrg({}), '');
});

// ── Usage mapping ───────────────────────────────────────────

const liveUsage = {
  five_hour: { utilization: 16, resets_at: '2026-11-26T03:19:59.582303+00:00', limit_dollars: null },
  seven_day: { utilization: 26, resets_at: '2026-11-30T05:59:59.582319+00:00', limit_dollars: null },
  seven_day_opus: null,
  seven_day_sonnet: null,
  maple_sundial: { utilization: 5.19, limit_dollars: 500, used_dollars: 25.98, resets_at: '2026-11-30T06:00:00+00:00' },
  extra_usage: { is_enabled: false, monthly_limit: null, used_credits: null, currency: null, decimal_places: null },
  limits: [
    { kind: 'session', group: 'session', percent: 16, resets_at: '2026-11-26T03:20:00.011703+00:00', scope: null, is_active: false },
    { kind: 'weekly_all', group: 'weekly', percent: 26, resets_at: '2026-11-30T06:00:00.011725+00:00', scope: null, is_active: true },
    {
      kind: 'weekly_scoped',
      group: 'weekly',
      percent: 7,
      resets_at: '2026-11-30T06:00:00+00:00',
      scope: { model: { id: null, display_name: 'Fable' }, surface: null },
      is_active: false,
    },
  ],
  spend: { used: { amount_minor: 0, currency: 'USD', exponent: 2 }, limit: null, percent: 0, enabled: false },
};

test('limits[] drives session, weekly and scoped windows', () => {
  const snap = mapToSnapshot(liveUsage, 'Max', NOW);
  assert.equal(snap.provider, 'claude');
  assert.equal(snap.planLabel, 'Max');
  assert.equal(snap.shortWindow.label, '5-Hour Window');
  assert.equal(snap.shortWindow.utilization, 16);
  assert.equal(snap.longWindow?.label, '7-Day Window');
  assert.equal(snap.longWindow?.utilization, 26);
  assert.equal(snap.extras.scopedWeekly?.length, 1);
  assert.equal(snap.extras.scopedWeekly?.[0]?.label, 'Fable Weekly');
  assert.equal(snap.extras.scopedWeekly?.[0]?.utilization, 7);
  assert.equal(snap.extras.opusSevenDay, undefined);
  assert.equal(snap.extras.usageCredits, undefined);
});

test('money objects and codename keys never become windows', () => {
  const snap = mapToSnapshot(
    {
      ...liveUsage,
      limits: [
        ...liveUsage.limits,
        { kind: 'weekly_scoped', percent: 5, limit_dollars: 500, used_dollars: 25, scope: { model: { display_name: 'Dollars' } } },
      ],
    },
    'Max',
    NOW,
  );
  assert.deepEqual(snap.extras.scopedWeekly?.map((w) => w.label), ['Fable Weekly']);
});

test('falls back to five_hour / seven_day when limits[] is absent', () => {
  const snap = mapToSnapshot(
    {
      five_hour: { utilization: 40, resets_at: '2026-11-26T03:00:00+00:00' },
      seven_day: { utilization: 12, resets_at: '2026-11-30T06:00:00+00:00' },
      seven_day_opus: { utilization: 9, resets_at: '2026-11-30T06:00:00+00:00' },
    },
    '',
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 40);
  assert.equal(snap.longWindow?.utilization, 12);
  assert.equal(snap.extras.opusSevenDay?.utilization, 9);
  assert.equal(snap.planLabel, '');
});

test('no session limit (Ultra) → no 5-hour window, never 0%', () => {
  const snap = mapToSnapshot(
    {
      five_hour: null,
      seven_day: { utilization: 30, resets_at: '2026-11-30T06:00:00+00:00' },
      limits: [liveUsage.limits[1]!],
    },
    'Ultra',
    NOW,
  );
  assert.equal(snap.shortWindow.label, '7-Day Window');
  assert.equal(snap.shortWindow.utilization, 26);
  assert.equal(snap.longWindow, null);
});

test('a response with no windows at all throws instead of showing 0%', () => {
  assert.throws(() => mapToSnapshot({ five_hour: null, seven_day: null }, 'Max', NOW));
});

// ── Usage credits ───────────────────────────────────────────

test('extra_usage maps when enabled, scaled by decimal_places', () => {
  const snap = mapToSnapshot(
    {
      ...liveUsage,
      extra_usage: { is_enabled: true, used_credits: 1250, monthly_limit: 5000, currency: 'USD', decimal_places: 2 },
    },
    'Max',
    NOW,
  );
  assert.deepEqual(snap.extras.usageCredits, { used: 12.5, limit: 50, currency: 'USD' });
});

test('spend maps when enabled and wins over extra_usage', () => {
  const snap = mapToSnapshot(
    {
      ...liveUsage,
      extra_usage: { is_enabled: true, used_credits: 1, monthly_limit: 2, currency: 'USD', decimal_places: 2 },
      spend: {
        enabled: true,
        used: { amount_minor: 2500, currency: 'USD', exponent: 2 },
        limit: { amount_minor: 10000, currency: 'USD', exponent: 2 },
      },
    },
    'Max',
    NOW,
  );
  assert.deepEqual(snap.extras.usageCredits, { used: 25, limit: 100, currency: 'USD' });
});

test('disabled credits are not shown even with a nonzero spend object', () => {
  const snap = mapToSnapshot(
    { ...liveUsage, spend: { enabled: false, used: { amount_minor: 900, currency: 'USD', exponent: 2 } } },
    'Max',
    NOW,
  );
  assert.equal(snap.extras.usageCredits, undefined);
});

// ── Review fixes ────────────────────────────────────────────

import { pickNonApiOrg } from './claude-map';

test('legacy five_hour/seven_day are ignored when limits[] is present without a session', () => {
  const snap = mapToSnapshot(
    {
      five_hour: { utilization: 99, resets_at: '2026-11-26T03:00:00+00:00' },
      seven_day: { utilization: 99, resets_at: '2026-11-30T06:00:00+00:00' },
      limits: [liveUsage.limits[1]!],
    },
    'Ultra',
    NOW,
  );
  assert.equal(snap.shortWindow.label, '7-Day Window');
  assert.equal(snap.shortWindow.utilization, 26);
  assert.equal(snap.longWindow, null);
});

test('null resets_at becomes an empty string, never null', () => {
  const snap = mapToSnapshot(
    { five_hour: { utilization: 5, resets_at: null }, seven_day: { utilization: 5, resets_at: null } },
    '',
    NOW,
  );
  assert.equal(snap.shortWindow.resetsAt, '');
  assert.equal(snap.longWindow?.resetsAt, '');
});

test('pickNonApiOrg: falls back to the first org that is not API-only', () => {
  assert.equal(pickNonApiOrg([apiOrg, { uuid: 'plain', capabilities: [] }])?.uuid, 'plain');
  assert.equal(pickNonApiOrg([apiOrg]), null);
  assert.equal(pickChatOrg([apiOrg, { uuid: 'plain', capabilities: [] }]), null);
});
