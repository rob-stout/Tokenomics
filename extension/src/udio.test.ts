/**
 * Unit tests for the Udio reader, against REAL captures (Free account,
 * 2026-11-23): fixtures/udio-api-usage.json and fixtures/udio-subscriptions.json.
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { AuthError, fetchUdioUsage, mapToSnapshot, type UdioUsage } from './udio';
import USAGE from './fixtures/udio-api-usage.json';
import SUBSCRIPTION from './fixtures/udio-subscriptions.json';

const DATA = USAGE.data as UdioUsage;
// Shortly after the capture's last_use (15:18:24Z).
const NOW = Date.UTC(2026, 10, 23, 15, 30, 0);

test('real capture: monthly is the short window (2 of 310, real renew_time)', () => {
  const snap = mapToSnapshot(DATA, SUBSCRIPTION, NOW);
  assert.equal(snap.provider, 'udio');
  assert.equal(snap.shortWindow.label, 'Monthly');
  assert.equal(snap.shortWindow.utilization, 1); // round(2/310*100)
  assert.equal(snap.shortWindow.resetsAt, '2026-12-23T15:17:51.795Z');
  assert.equal(snap.shortWindow.windowDurationSec, 30 * 86400);
  assert.equal(snap.shortWindow.sublabelOverride, undefined); // live countdown instead
});

test('real capture: daily is the long window (2 of 10, resets start_day + 24h)', () => {
  const daily = mapToSnapshot(DATA, SUBSCRIPTION, NOW).longWindow;
  assert.ok(daily);
  assert.equal(daily.label, 'Daily');
  assert.equal(daily.utilization, 20);
  assert.equal(daily.resetsAt, '2026-11-24T15:17:51.795Z');
  assert.equal(daily.windowDurationSec, 86400);
});

test('plan label comes from /api/subscriptions; falls back to tier', () => {
  assert.equal(mapToSnapshot(DATA, SUBSCRIPTION, NOW).planLabel, 'Free');
  assert.equal(mapToSnapshot(DATA, { plan: 'pro' }, NOW).planLabel, 'Pro');
  assert.equal(mapToSnapshot(DATA, null, NOW).planLabel, 'Free'); // tier: "free"
  assert.equal(mapToSnapshot({}, null, NOW).planLabel, 'Udio');
});

test('daily window already rolled → 0 used, next 24h boundary in the future', () => {
  const later = NOW + 30 * 3600 * 1000; // 30h after start_day... start was 15:17, now Nov 24 21:30
  const daily = mapToSnapshot(DATA, SUBSCRIPTION, later).longWindow;
  assert.ok(daily);
  assert.equal(daily.utilization, 0);
  assert.equal(daily.resetsAt, '2026-11-25T15:17:51.795Z');
});

test('limits capped and zero limit safe', () => {
  const over = mapToSnapshot({ ...DATA, monthly_used: 999 }, null, NOW);
  assert.equal(over.shortWindow.utilization, 100);
  const none = mapToSnapshot({ ...DATA, monthly_limit: 0, daily_throttle_limit: 0 }, null, NOW);
  assert.equal(none.shortWindow.utilization, 0);
  assert.equal(none.longWindow?.utilization, 0);
});

test('empty usage → 0%, placeholder dates in the future', () => {
  const snap = mapToSnapshot({}, null, NOW);
  assert.equal(snap.shortWindow.utilization, 0);
  assert.ok(new Date(snap.shortWindow.resetsAt).getTime() > NOW);
  assert.ok(new Date(snap.longWindow?.resetsAt ?? '').getTime() > NOW);
});

// ── fetch layer ─────────────────────────────────────────────

function stubFetch(routes: Record<string, { status: number; body?: unknown }>) {
  const calls: { url: string; credentials?: string }[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (url: string, init?: { credentials?: string }) => {
    calls.push({ url, credentials: init?.credentials });
    const r = routes[url] ?? { status: 404 };
    return { status: r.status, ok: r.status >= 200 && r.status < 300, json: async () => r.body };
  }) as unknown as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

const USAGE_URL = 'https://www.udio.com/api/users/current/api-usage';
const SUB_URL = 'https://www.udio.com/api/subscriptions';

test('fetch: both endpoints, same-origin cookies, real shapes', async () => {
  const stub = stubFetch({
    [USAGE_URL]: { status: 200, body: USAGE },
    [SUB_URL]: { status: 200, body: SUBSCRIPTION },
  });
  try {
    const snap = await fetchUdioUsage();
    assert.equal(snap.planLabel, 'Free');
    assert.equal(snap.shortWindow.resetsAt, '2026-12-23T15:17:51.795Z');
    assert.deepEqual(stub.calls.map((c) => c.url).sort(), [SUB_URL, USAGE_URL].sort());
    assert.ok(stub.calls.every((c) => c.credentials === 'include'));
  } finally {
    stub.restore();
  }
});

test('fetch: 401 on usage → AuthError', async () => {
  const stub = stubFetch({ [USAGE_URL]: { status: 401 }, [SUB_URL]: { status: 401 } });
  try {
    await assert.rejects(fetchUdioUsage(), (e: unknown) => e instanceof AuthError);
  } finally {
    stub.restore();
  }
});

test('fetch: subscriptions failing still yields usage, plan from tier', async () => {
  const stub = stubFetch({ [USAGE_URL]: { status: 200, body: USAGE }, [SUB_URL]: { status: 500 } });
  try {
    assert.equal((await fetchUdioUsage()).planLabel, 'Free');
  } finally {
    stub.restore();
  }
});

test('paid limits come from the API, not a hard-coded table', () => {
  const snap = mapToSnapshot(
    { ...DATA, tier: 'pro', monthly_used: 600, monthly_limit: 2400, daily_used: 5, daily_throttle_limit: 20 },
    { plan: 'pro' },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 25);
  assert.equal(snap.longWindow?.utilization, 25);
  assert.equal(snap.planLabel, 'Pro');
});
