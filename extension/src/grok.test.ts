/**
 * Unit tests for the Grok rate-limit parser.
 *
 * All tests exercise `mapToSnapshot` directly — the pure mapper is the only
 * logic worth unit-testing; the fetch layer is covered by end-to-end capture.
 *
 * Fixtures inline the REAL API response captured live 2026-06-01:
 *   { "windowSizeSeconds": 86400, "remainingQueries": 20, "totalQueries": 20,
 *     "lowEffortRateLimits": null, "highEffortRateLimits": null }
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mapToSnapshot } from './grok';

// Fixed "now" so resetsAt assertions are deterministic.
// 2026-06-01T00:00:00.000Z
const NOW = 1_748_736_000_000;
const DAY_SEC = 86400;

// ── Real fixture (fresh account, no usage) ─────────────────

test('real fixture: 20/20 remaining → 0% utilization', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 20, totalQueries: 20 },
    NOW,
  );
  assert.equal(snap.provider, 'grok');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.label, 'Fast Queries');
  assert.equal(snap.shortWindow.sublabelOverride, '20 of 20 left');
  assert.equal(snap.planLabel, 'Grok');
  assert.equal(snap.longWindow, null);
  assert.equal(snap.estimated, false);
});

// ── Partial usage ───────────────────────────────────────────

test('5 of 20 used → 25% utilization', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 15, totalQueries: 20 },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 25);
  assert.equal(snap.shortWindow.sublabelOverride, '15 of 20 left');
});

test('all 20 queries used → 100% utilization', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 0, totalQueries: 20 },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 100);
  assert.equal(snap.shortWindow.sublabelOverride, '0 of 20 left');
});

// ── Edge cases ──────────────────────────────────────────────

test('totalQueries = 0 → 0% utilization (no divide-by-zero)', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 0, totalQueries: 0 },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, '0 of 0 left');
});

test('completely empty body → safe defaults, no throw', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.provider, 'grok');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.equal(snap.shortWindow.sublabelOverride, '0 of 0 left');
  assert.equal(snap.longWindow, null);
});

test('resetsAt is now + windowSizeSeconds', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 10, totalQueries: 20 },
    NOW,
  );
  const expectedResetsAt = new Date(NOW + DAY_SEC * 1000).toISOString();
  assert.equal(snap.shortWindow.resetsAt, expectedResetsAt);
});

test('windowDurationSec defaults to 86400 when field is missing', () => {
  const snap = mapToSnapshot({ remainingQueries: 10, totalQueries: 20 }, NOW);
  assert.equal(snap.shortWindow.windowDurationSec, DAY_SEC);
});

test('capturedAt matches the `now` parameter', () => {
  const snap = mapToSnapshot({}, NOW);
  assert.equal(snap.capturedAt, NOW);
});

// ── Utilization math ─────────────────────────────────────────

test('utilization rounds correctly: 1/3 → 33%', () => {
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 2, totalQueries: 3 },
    NOW,
  );
  assert.equal(snap.shortWindow.utilization, 33);
});

test('utilization clamps to 100 when remaining > total (unexpected data)', () => {
  // remaining > total would mean negative used — treated as 0% used (clamp at 0).
  const snap = mapToSnapshot(
    { windowSizeSeconds: 86400, remainingQueries: 25, totalQueries: 20 },
    NOW,
  );
  // used = max(0, 20 - 25) = 0 → 0%
  assert.equal(snap.shortWindow.utilization, 0);
});

// ── Paid: subscriptions + gRPC-web credits pool ─────────────

import {
  decodeProto,
  firstGrpcDataFrame,
  mapPoolToSnapshot,
  parseCreditsMessage,
  parseSubscriptions,
} from './grok';

// Tiny protobuf encoders so fixtures match the documented wire layout.
function varint(n: number): number[] {
  const out: number[] = [];
  let v = n;
  while (v >= 0x80) {
    out.push((v % 128) | 0x80);
    v = Math.floor(v / 128);
  }
  out.push(v);
  return out;
}
const tag = (field: number, wire: number) => varint(field * 8 + wire);
function f32(field: number, value: number): number[] {
  const b = new Uint8Array(4);
  new DataView(b.buffer).setFloat32(0, value, true);
  return [...tag(field, 5), ...b];
}
const vint = (field: number, value: number) => [...tag(field, 0), ...varint(value)];
const lenDelim = (field: number, inner: number[]) => [...tag(field, 2), ...varint(inner.length), ...inner];
function grpcFrame(message: number[], flag = 0): Uint8Array {
  const len = message.length;
  return new Uint8Array([flag, (len >>> 24) & 255, (len >>> 16) & 255, (len >>> 8) & 255, len & 255, ...message]);
}

const PERIOD_END_SEC = 1_795_000_000;

function creditsMessage(opts: { percent?: number; end?: number; products?: Array<[number, number | null]> }): Uint8Array {
  const config: number[] = [];
  if (opts.percent !== undefined) config.push(...f32(1, opts.percent));
  if (opts.end !== undefined) config.push(...lenDelim(5, vint(1, opts.end)));
  for (const [id, pct] of opts.products ?? []) {
    config.push(...lenDelim(7, [...vint(1, id), ...(pct === null ? [] : f32(2, pct))]));
  }
  return new Uint8Array(lenDelim(1, config));
}

test('parseSubscriptions: active tier → paid, SURFACE_DISPLAY wins', () => {
  const info = parseSubscriptions({
    subscriptions: [
      { tier: 'SUBSCRIPTION_TIER_GROK_PRO', status: 'SUBSCRIPTION_STATUS_INACTIVE' },
      { tier: 'SUBSCRIPTION_TIER_SUPER_GROK_PRO', status: 'SUBSCRIPTION_STATUS_ACTIVE' },
    ],
    dominantPlan: { surfaceNames: { SURFACE_DISPLAY: 'SuperGrok Heavy' } },
  });
  assert.deepEqual(info, { paid: true, planLabel: 'SuperGrok Heavy' });
});

test('parseSubscriptions: falls back to the tier name', () => {
  const info = parseSubscriptions({
    subscriptions: [{ tier: 'SUBSCRIPTION_TIER_GROK_PRO', status: 'SUBSCRIPTION_STATUS_ACTIVE' }],
  });
  assert.deepEqual(info, { paid: true, planLabel: 'SuperGrok' });
});

test('parseSubscriptions: no active subscription → free', () => {
  assert.equal(parseSubscriptions({ subscriptions: [] }).paid, false);
  assert.equal(
    parseSubscriptions({ subscriptions: [{ tier: 'SUBSCRIPTION_TIER_GROK_PRO', status: 'SUBSCRIPTION_STATUS_INACTIVE' }] }).paid,
    false,
  );
  assert.equal(parseSubscriptions({}).paid, false);
});

test('credits pool: percent, period end and known products decode', () => {
  const pool = parseCreditsMessage(
    creditsMessage({ percent: 42.5, end: PERIOD_END_SEC, products: [[2, 10], [4, 30], [5, 99]] }),
  );
  assert.ok(pool);
  assert.equal(pool!.usedPercent, 42.5);
  assert.equal(pool!.resetAtMs, PERIOD_END_SEC * 1000);
  // Enum 5 is not mapped (sources disagree), so it is dropped.
  assert.deepEqual(pool!.products, [
    { name: 'Grok Build', percent: 10 },
    { name: 'Chat', percent: 30 },
  ]);
});

test('credits pool: missing percent is a genuine 0% (proto3 omits zeros)', () => {
  const pool = parseCreditsMessage(creditsMessage({ end: PERIOD_END_SEC }));
  assert.equal(pool!.usedPercent, 0);
  assert.equal(pool!.resetAtMs, PERIOD_END_SEC * 1000);
});

test('credits pool: unrecognisable message → null, not a fake 0%', () => {
  assert.equal(parseCreditsMessage(new Uint8Array([])), null);
  assert.equal(parseCreditsMessage(new Uint8Array(lenDelim(1, []))), null);
  assert.equal(parseCreditsMessage(new Uint8Array(lenDelim(9, vint(1, 5)))), null);
});

test('firstGrpcDataFrame skips trailer frames and reads the data frame', () => {
  const msg = Array.from(creditsMessage({ percent: 7 }));
  const trailer = grpcFrame([...new TextEncoder().encode('grpc-status: 0')], 0x80);
  const body = new Uint8Array([...grpcFrame(msg), ...trailer]);
  const frame = firstGrpcDataFrame(body);
  assert.ok(frame);
  assert.equal(parseCreditsMessage(frame!)!.usedPercent, 7);
  assert.equal(firstGrpcDataFrame(trailer), null);
  assert.equal(firstGrpcDataFrame(new Uint8Array(5)) !== null, true); // empty data frame = zero-length message
});

test('decodeProto handles multi-byte varints', () => {
  const fields = decodeProto(new Uint8Array(vint(1, 1_795_000_000)));
  assert.equal(fields.get(1)?.[0], 1_795_000_000);
});

test('mapPoolToSnapshot: one Weekly window with the period end as reset', () => {
  const pool = parseCreditsMessage(creditsMessage({ percent: 41.6, end: PERIOD_END_SEC }))!;
  const snap = mapPoolToSnapshot(pool, 'SuperGrok', NOW);
  assert.equal(snap.provider, 'grok');
  assert.equal(snap.planLabel, 'SuperGrok');
  assert.equal(snap.shortWindow.label, 'Weekly');
  assert.equal(snap.shortWindow.utilization, 42);
  assert.equal(snap.shortWindow.resetsAt, new Date(PERIOD_END_SEC * 1000).toISOString());
  assert.equal(snap.shortWindow.windowDurationSec, 7 * 86400);
  assert.equal(snap.longWindow, null);
  assert.equal(snap.estimated, false);
});

test('mapToSnapshot accepts a plan label for the free path', () => {
  const snap = mapToSnapshot({ windowSizeSeconds: 86400, remainingQueries: 20, totalQueries: 20 }, NOW, 'Free');
  assert.equal(snap.planLabel, 'Free');
});

// ── Review fixes: cache, auth, content-type, missing period end ──

import { fetchGrokUsage, resolvePlanInfo, type GrokPlanInfo } from './grok';
import { PLAN_CACHE_TTL_MS } from './snapshot';

type StubReply = { status?: number; json?: unknown; bytes?: Uint8Array; contentType?: string };

function stubGrokFetch(routes: Record<string, StubReply>) {
  const calls: string[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (url: string) => {
    calls.push(url);
    const r = routes[url] ?? { status: 404 };
    const status = r.status ?? 200;
    return {
      status,
      ok: status >= 200 && status < 300,
      headers: { get: (h: string) => (h.toLowerCase() === 'content-type' ? (r.contentType ?? 'application/json') : null) },
      json: async () => r.json ?? {},
      arrayBuffer: async () => (r.bytes ?? new Uint8Array()).buffer.slice(0),
    };
  }) as unknown as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

const SUBS = 'https://grok.com/rest/subscriptions';
const CREDITS = 'https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig';
const LIMITS = 'https://grok.com/rest/rate-limits';
const ACTIVE = { subscriptions: [{ tier: 'SUBSCRIPTION_TIER_GROK_PRO', status: 'SUBSCRIPTION_STATUS_ACTIVE' }] };
const FREE_LIMITS = { status: 200, json: { windowSizeSeconds: 86400, remainingQueries: 10, totalQueries: 20 } };

test('subscriptions 401 → unknown plan, rate-limits decides (no AuthError from the plan lookup)', async () => {
  const stub = stubGrokFetch({ [SUBS]: { status: 401 }, [LIMITS]: FREE_LIMITS });
  try {
    const { snapshot, plan } = await fetchGrokUsage(null);
    assert.equal(snapshot.shortWindow.label, 'Fast Queries');
    assert.equal(snapshot.planLabel, 'Grok');
    assert.equal(plan, null);
  } finally {
    stub.restore();
  }
});

test('subscriptions 401 and rate-limits 401 → AuthError', async () => {
  const stub = stubGrokFetch({ [SUBS]: { status: 401 }, [LIMITS]: { status: 401 } });
  try {
    await assert.rejects(fetchGrokUsage(null), (e: unknown) => e instanceof Error && e.name === 'AuthError');
  } finally {
    stub.restore();
  }
});

test('paid pool without a period end falls through to rate-limits (never an empty reset)', async () => {
  const noEnd = grpcFrame(Array.from(creditsMessage({ percent: 30 })));
  const stub = stubGrokFetch({
    [SUBS]: { json: ACTIVE },
    [CREDITS]: { bytes: noEnd, contentType: 'application/grpc-web+proto' },
    [LIMITS]: FREE_LIMITS,
  });
  try {
    const { snapshot } = await fetchGrokUsage(null);
    assert.equal(snapshot.shortWindow.label, 'Fast Queries');
    assert.notEqual(snapshot.shortWindow.resetsAt, '');
  } finally {
    stub.restore();
  }
});

test('paid pool with a period end → Weekly window', async () => {
  const ok = grpcFrame(Array.from(creditsMessage({ percent: 30, end: PERIOD_END_SEC })));
  const stub = stubGrokFetch({
    [SUBS]: { json: ACTIVE },
    [CREDITS]: { bytes: ok, contentType: 'application/grpc-web+proto' },
  });
  try {
    const { snapshot, plan } = await fetchGrokUsage(null);
    assert.equal(snapshot.shortWindow.label, 'Weekly');
    assert.equal(plan?.value.paid, true);
  } finally {
    stub.restore();
  }
});

test('credits reply that is not grpc-web (HTML) is ignored', async () => {
  const ok = grpcFrame(Array.from(creditsMessage({ percent: 30, end: PERIOD_END_SEC })));
  const stub = stubGrokFetch({
    [SUBS]: { json: ACTIVE },
    [CREDITS]: { bytes: ok, contentType: 'text/html' },
    [LIMITS]: FREE_LIMITS,
  });
  try {
    const { snapshot } = await fetchGrokUsage(null);
    assert.equal(snapshot.shortWindow.label, 'Fast Queries');
  } finally {
    stub.restore();
  }
});

test('fresh cached plan skips the subscriptions request', async () => {
  const cached = { value: { paid: false, planLabel: '' } as GrokPlanInfo, at: Date.now() - 1000 };
  const stub = stubGrokFetch({ [LIMITS]: FREE_LIMITS });
  try {
    const { snapshot } = await fetchGrokUsage(cached);
    assert.equal(stub.calls.includes(SUBS), false);
    assert.equal(snapshot.planLabel, 'Free');
  } finally {
    stub.restore();
  }
});

test('resolvePlanInfo: stale cache + failed lookup keeps the last known value', async () => {
  const stale = { value: { paid: true, planLabel: 'SuperGrok' } as GrokPlanInfo, at: Date.now() - PLAN_CACHE_TTL_MS - 5 };
  const got = await resolvePlanInfo(stale, Date.now(), async () => null);
  assert.equal(got?.value.planLabel, 'SuperGrok');
});
