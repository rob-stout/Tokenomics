/**
 * Unit tests for the ElevenLabs subscription parser.
 *
 * All tests exercise `mapToSnapshot` directly — the pure mapper is the only
 * logic worth testing; the fetch layer is tested end-to-end by a human capture.
 *
 * Auth has been corrected to Firebase Bearer token (api.us.elevenlabs.io).
 * The mapper is unchanged — character_count/character_limit → utilization%,
 * next_character_count_reset_unix → resetsAt. A past reset timestamp is rolled
 * forward by calendar months (free accounts report a stale first reset date).
 *
 * Real response (confirmed 2026-06-01):
 *   { "tier": "free", "character_count": 0, "character_limit": 10000,
 *     "next_character_count_reset_unix": 1777606325, "status": "free" }
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { nextMonthlyReset, mapToSnapshot } from './elevenlabs';

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
  assert.equal(snap.shortWindow.label, 'Credits');
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

test('past next_character_count_reset_unix → rolled forward by months', () => {
  // Seen live on a Free account: reset reported as May 1 in late November.
  const now = Date.UTC(2026, 10, 23, 15, 0, 0); // 2026-11-23
  const stale = Date.UTC(2026, 4, 1, 3, 32, 5) / 1000; // 2026-05-01
  const snap = mapToSnapshot(
    { character_count: 0, character_limit: 10_000, next_character_count_reset_unix: stale },
    now,
  );
  assert.equal(snap.shortWindow.resetsAt, '2026-12-01T03:32:05.000Z');
});

test('nextMonthlyReset clamps to the last day of shorter months', () => {
  const now = Date.UTC(2026, 1, 10); // 2026-02-10
  const jan31 = Date.UTC(2026, 0, 31, 12);
  assert.equal(nextMonthlyReset(jan31, now), '2026-02-28T12:00:00.000Z');
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

// ── API key path ────────────────────────────────────────────

import { AuthError, authHeaders, fetchElevenLabsUsage } from './elevenlabs';

/** Replaces global fetch for one test; returns the captured requests. */
function stubFetch(status: number, body: unknown = {}) {
  const calls: { url: string; headers: Record<string, string> }[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (url: string, init?: { headers?: Record<string, string> }) => {
    calls.push({ url, headers: init?.headers ?? {} });
    return { status, ok: status >= 200 && status < 300, json: async () => body };
  }) as unknown as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

test('api key: sends only xi-api-key, never Authorization', () => {
  const headers = authHeaders({ kind: 'apiKey', key: 'sk_test' });
  assert.deepEqual(headers, { 'xi-api-key': 'sk_test' });
  assert.equal('Authorization' in headers, false);
});

test('captured token: still sends Bearer only', () => {
  assert.deepEqual(authHeaders({ kind: 'bearer', token: 'abc' }), { Authorization: 'Bearer abc' });
});

test('api key: hits the official endpoint and maps the response', async () => {
  const stub = stubFetch(200, {
    tier: 'creator', character_count: 900, character_limit: 1000,
    next_character_count_reset_unix: Math.floor(Date.now() / 1000) + 86400,
  });
  try {
    const snap = await fetchElevenLabsUsage({ kind: 'apiKey', key: 'sk_test' });
    assert.equal(stub.calls[0]?.url, 'https://api.us.elevenlabs.io/v1/user/subscription');
    assert.deepEqual(stub.calls[0]?.headers, { 'xi-api-key': 'sk_test' });
    assert.equal(snap.shortWindow.utilization, 90);
    assert.equal(snap.planLabel, 'Creator');
  } finally {
    stub.restore();
  }
});

test('api key: 401 → AuthError with a key-specific message', async () => {
  const stub = stubFetch(401);
  try {
    await assert.rejects(
      fetchElevenLabsUsage({ kind: 'apiKey', key: 'bad' }),
      (err: unknown) =>
        err instanceof AuthError && /API key/.test(err.message) && /User: read/.test(err.message),
    );
  } finally {
    stub.restore();
  }
});
