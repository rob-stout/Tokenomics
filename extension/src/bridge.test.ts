/**
 * Unit tests for bridge.ts — sendBridgeBatch + scheduleBridgeSend.
 *
 * Run via `npm run test`.
 *
 * Uses installMockChrome() from __mocks__/chrome.ts to control
 * sendNativeMessage responses and bridge storage. webextension-polyfill
 * delegates to globalThis.chrome at call time, so the mock covers both
 * the bridge's direct chrome.* calls and storage.ts's browser.* calls.
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { installMockChrome, type MockChrome } from './__mocks__/chrome';
import type { BridgeResponse, BridgeSnapshot } from './bridge-types';
import { BRIDGE_SCHEMA_VERSION } from './bridge-types';

// ── Helpers ──────────────────────────────────────────────────────

function makeNativeResponse(overrides: Partial<BridgeResponse> = {}): BridgeResponse {
  return {
    ok: true,
    bridgeSchemaVersion: BRIDGE_SCHEMA_VERSION,
    macAppVersion: '2.9.0',
    ackedAt: new Date().toISOString(),
    nativeSnapshots: [],
    settings: { providerVisibility: {} },
    commands: [],
    ...overrides,
  };
}

function makeNativeSnapshot(provider: string, capturedAt: string): BridgeSnapshot {
  return {
    provider,
    capturedAt,
    shortWindow: {
      label: '5h',
      utilization: 0.5,
      resetsAt: '2026-05-14T23:00:00.000Z',
      windowDurationSec: 18000,
    },
    longWindow: null,
    planLabel: 'Pro',
  };
}

/** Wait for all microtasks and a short macro-task pause. */
function flushAsync(ms = 20): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ── Test state ───────────────────────────────────────────────────

// Re-imported fresh each time via dynamic import after chrome mock is installed.
// We can't use static imports for bridge because it closes over module-level
// state. Instead we import once and rely on beforeEach resetting chrome + storage.

let mock: MockChrome;

// We import bridge once at module level — each test must reset
// inFlightPromise / debounceTimer state. We do this by calling sendBridgeBatch
// fresh in each test after installing a new chrome mock. Module-level state in
// bridge.ts (inFlightPromise, debounceTimer) persists across tests but that
// only matters for the single-flight and debounce tests where we drive them
// within a single test body.
import {
  sendBridgeBatch,
  scheduleBridgeSend,
  registerRefreshWebProvidersHandler,
} from './bridge';

// ── Test 1: Wire serializer ──────────────────────────────────────

test('wire serializer: request JSON has ISO capturedAt and 0-1 utilization', async () => {
  let capturedRequest: unknown = null;

  // Install mock that captures the outbound request
  mock = installMockChrome({ nativeMessageResponse: makeNativeResponse() });
  const origSend = mock.runtime.sendNativeMessage.bind(mock.runtime);
  mock.runtime.sendNativeMessage = (_host, message, callback) => {
    capturedRequest = message;
    origSend(_host, message, callback);
  };
  (globalThis as any).chrome = mock;

  // Write a Claude snapshot into storage (utilization 0-100, capturedAt as ms)
  await new Promise<void>((resolve) => {
    chrome.storage.local.set(
      {
        claudeSnapshot: {
          provider: 'claude',
          shortWindow: {
            label: '5h',
            utilization: 42,
            resetsAt: '2026-05-14T23:00:00.000Z',
            windowDurationSec: 18000,
          },
          longWindow: null,
          extras: {},
          planLabel: 'Pro',
          capturedAt: 1_747_248_000_000, // fixed ms epoch
          estimated: false,
        },
      },
      resolve,
    );
  });

  await sendBridgeBatch('ping');

  assert.ok(capturedRequest, 'sendNativeMessage was not called');
  const req = capturedRequest as Record<string, unknown>;

  assert.equal(req['schemaVersion'], 1, 'schemaVersion should be 1');
  assert.equal(typeof req['envelopeSentAt'], 'string', 'envelopeSentAt should be a string');
  // ISO 8601 check
  assert.ok((req['envelopeSentAt'] as string).includes('T'), 'envelopeSentAt should be ISO 8601');

  const snaps = req['snapshots'] as BridgeSnapshot[];
  assert.equal(snaps.length, 1, 'should have 1 snapshot');
  const snap = snaps[0];

  // capturedAt must be ISO 8601, not a number
  assert.equal(typeof snap.capturedAt, 'string', 'capturedAt should be a string');
  assert.ok(snap.capturedAt.includes('T'), 'capturedAt should be ISO 8601');
  assert.equal(new Date(snap.capturedAt).getTime(), 1_747_248_000_000, 'capturedAt round-trips correctly');

  // utilization must be 0-1, not 0-100
  assert.ok(snap.shortWindow.utilization >= 0 && snap.shortWindow.utilization <= 1, 'utilization should be 0-1');
  assert.ok(Math.abs(snap.shortWindow.utilization - 0.42) < 0.001, 'utilization should be ~0.42');
});

// ── Regression: every web reader is transmitted (no silent drops) ──
// The bridge used to hard-code claude/midjourney/chatgpt and silently drop the
// extension-only readers (geminiConsumer/grok/perplexity/leonardo) — they were
// computed + badged but never reached the Mac. Now the gather iterates all keys.
test('gather: extension-only readers reach the Mac', async () => {
  let capturedRequest: unknown = null;
  mock = installMockChrome({ nativeMessageResponse: makeNativeResponse() });
  const origSend = mock.runtime.sendNativeMessage.bind(mock.runtime);
  mock.runtime.sendNativeMessage = (_host, message, callback) => {
    capturedRequest = message;
    origSend(_host, message, callback);
  };
  (globalThis as any).chrome = mock;

  const mkSnap = (provider: string) => ({
    provider,
    shortWindow: { label: 'w', utilization: 10, resetsAt: '2026-05-14T23:00:00.000Z', windowDurationSec: 3600 },
    longWindow: null,
    extras: {},
    planLabel: '',
    capturedAt: 1_747_248_000_000,
    estimated: false,
  });

  await new Promise<void>((resolve) => {
    chrome.storage.local.set(
      {
        geminiConsumerSnapshot: mkSnap('geminiConsumer'),
        grokSnapshot: mkSnap('grok'),
        perplexitySnapshot: mkSnap('perplexity'),
        leonardoSnapshot: mkSnap('leonardo'),
      },
      resolve,
    );
  });

  await sendBridgeBatch('snapshot');

  const req = capturedRequest as Record<string, unknown>;
  const ids = (req['snapshots'] as BridgeSnapshot[]).map((s) => s.provider);
  for (const id of ['geminiConsumer', 'grok', 'perplexity', 'leonardo']) {
    assert.ok(ids.includes(id), `bridge must transmit ${id} (was being silently dropped)`);
  }
});

// ── Test 2: Debounce ─────────────────────────────────────────────

test('debounce: 5 scheduleBridgeSend calls within 100ms produce exactly 1 sendNativeMessage', async () => {
  mock = installMockChrome({ nativeMessageResponse: makeNativeResponse() });
  let callCount = 0;
  const origSend = mock.runtime.sendNativeMessage.bind(mock.runtime);
  mock.runtime.sendNativeMessage = (host, message, callback) => {
    callCount++;
    origSend(host, message, callback);
  };
  (globalThis as any).chrome = mock;

  scheduleBridgeSend('snapshot');
  scheduleBridgeSend('snapshot');
  scheduleBridgeSend('snapshot');
  scheduleBridgeSend('snapshot');
  scheduleBridgeSend('snapshot');

  // Wait for debounce to fire (500ms) plus a bit more
  await flushAsync(600);

  assert.equal(callCount, 1, 'Expected exactly 1 sendNativeMessage invocation');
});

// ── Test 3: Single-flight ────────────────────────────────────────

test('single-flight: two concurrent sendBridgeBatch calls share one sendNativeMessage', async () => {
  mock = installMockChrome({ nativeMessageResponse: makeNativeResponse() });
  let callCount = 0;
  const origSend = mock.runtime.sendNativeMessage.bind(mock.runtime);
  mock.runtime.sendNativeMessage = (host, message, callback) => {
    callCount++;
    origSend(host, message, callback);
  };
  (globalThis as any).chrome = mock;

  const [r1, r2] = await Promise.all([sendBridgeBatch('ping'), sendBridgeBatch('ping')]);

  assert.equal(callCount, 1, 'Expected exactly 1 underlying sendNativeMessage call');
  assert.deepEqual(r1, r2, 'Both callers should resolve to the same value');
});

// ── Test 4: Settings merge — incoming wins ───────────────────────

test('settings merge: incoming wins when its lastChangedAt is later', async () => {
  const T0 = '2026-05-14T10:00:00.000Z';
  const T1 = '2026-05-14T11:00:00.000Z'; // T1 > T0

  mock = installMockChrome({
    nativeMessageResponse: makeNativeResponse({
      settings: {
        providerVisibility: {
          midjourney: { enabled: false, lastChangedAt: T1 },
        },
      },
    }),
  });
  (globalThis as any).chrome = mock;

  // Seed local visibility with enabled=true at T0
  await new Promise<void>((resolve) => {
    chrome.storage.local.set(
      { providerVisibility: { midjourney: { enabled: true, lastChangedAt: T0 } } },
      resolve,
    );
  });

  await sendBridgeBatch('settings');

  const stored = await new Promise<Record<string, unknown>>((resolve) => {
    chrome.storage.local.get(['providerVisibility'], resolve);
  });
  const visibility = stored['providerVisibility'] as Record<string, { enabled: boolean; lastChangedAt: string }>;
  assert.equal(visibility['midjourney']?.enabled, false, 'Incoming (later) value should win');
  assert.equal(visibility['midjourney']?.lastChangedAt, T1);
});

// ── Test 5: Settings merge — local wins ─────────────────────────

test('settings merge: local wins when its lastChangedAt is later', async () => {
  const T0 = '2026-05-14T10:00:00.000Z'; // T0 < T1
  const T1 = '2026-05-14T11:00:00.000Z';

  mock = installMockChrome({
    nativeMessageResponse: makeNativeResponse({
      settings: {
        providerVisibility: {
          midjourney: { enabled: false, lastChangedAt: T0 }, // older
        },
      },
    }),
  });
  (globalThis as any).chrome = mock;

  // Seed local with enabled=true at T1 (later)
  await new Promise<void>((resolve) => {
    chrome.storage.local.set(
      { providerVisibility: { midjourney: { enabled: true, lastChangedAt: T1 } } },
      resolve,
    );
  });

  await sendBridgeBatch('settings');

  const stored = await new Promise<Record<string, unknown>>((resolve) => {
    chrome.storage.local.get(['providerVisibility'], resolve);
  });
  const visibility = stored['providerVisibility'] as Record<string, { enabled: boolean; lastChangedAt: string }>;
  assert.equal(visibility['midjourney']?.enabled, true, 'Local (later) value should be retained');
  assert.equal(visibility['midjourney']?.lastChangedAt, T1);
});

// ── Test 6: nativeSnapshots stored; older does not overwrite ─────

test('nativeSnapshots: response snapshot stored; older snapshot for same provider does not overwrite', async () => {
  const NEWER = '2026-05-14T18:00:00.000Z';
  const OLDER = '2026-05-14T16:00:00.000Z';

  const newerSnap = makeNativeSnapshot('codex', NEWER);
  const olderSnap = makeNativeSnapshot('codex', OLDER);

  // Use a mutable response holder so both calls share the same storage backing
  let currentResponse = makeNativeResponse({ nativeSnapshots: [newerSnap] });

  mock = installMockChrome({});
  mock.runtime.sendNativeMessage = (_host, _message, callback) => {
    callback(currentResponse);
  };
  (globalThis as any).chrome = mock;

  // First call — stores the newer snapshot
  await sendBridgeBatch('snapshot');

  let stored = await new Promise<Record<string, unknown>>((resolve) => {
    chrome.storage.local.get(['nativeSnapshots'], resolve);
  });
  const map1 = stored['nativeSnapshots'] as Record<string, BridgeSnapshot>;
  assert.ok(map1['codex'], 'codex snapshot should be stored');
  assert.equal(map1['codex'].capturedAt, NEWER);

  // Second call — response has an OLDER snapshot for the same provider
  currentResponse = makeNativeResponse({ nativeSnapshots: [olderSnap] });

  await sendBridgeBatch('snapshot');

  stored = await new Promise<Record<string, unknown>>((resolve) => {
    chrome.storage.local.get(['nativeSnapshots'], resolve);
  });
  const map2 = stored['nativeSnapshots'] as Record<string, BridgeSnapshot>;
  assert.equal(map2['codex'].capturedAt, NEWER, 'Older incoming snapshot should not overwrite newer stored one');
});

// ── Test 7: Error path ───────────────────────────────────────────

test('error path: lastError causes sendBridgeBatch to resolve null and append bridgeStatus error', async () => {
  mock = installMockChrome({ nativeMessageError: 'Specified native messaging host not found.' });
  (globalThis as any).chrome = mock;

  const result = await sendBridgeBatch('ping');

  assert.equal(result, null, 'Should resolve to null on error');

  const stored = await new Promise<Record<string, unknown>>((resolve) => {
    chrome.storage.local.get(['bridgeState'], resolve);
  });
  const state = stored['bridgeState'] as { status: Array<{ level: string }> };
  assert.ok(Array.isArray(state?.status), 'bridgeState.status should be an array');
  const lastEntry = state.status[state.status.length - 1];
  assert.equal(lastEntry?.level, 'error', 'Last status entry should be level=error');
});

// ── Test 8: Unknown command silently ignored ─────────────────────

test('unknown command: does not throw; appends a warn-level status entry', async () => {
  mock = installMockChrome({
    nativeMessageResponse: makeNativeResponse({
      commands: [{ kind: 'alienOverlord' }],
    }),
  });
  (globalThis as any).chrome = mock;

  // Register a no-op handler so refreshWebProviders is wired
  registerRefreshWebProvidersHandler(() => undefined);

  let threw = false;
  try {
    await sendBridgeBatch('ping');
  } catch {
    threw = true;
  }

  assert.equal(threw, false, 'Should not throw on unknown command');

  const stored = await new Promise<Record<string, unknown>>((resolve) => {
    chrome.storage.local.get(['bridgeState'], resolve);
  });
  const state = stored['bridgeState'] as { status: Array<{ level: string; message: string }> };
  const warnEntry = state.status.find((e) => e.level === 'warn');
  assert.ok(warnEntry, 'Should have a warn-level status entry for unknown command');
  assert.ok(warnEntry.message.includes('alienOverlord'), 'Warn message should mention the unknown command kind');
});

// ── Test 9: Schema version cached ───────────────────────────────

test('schema version cached: bridgeState.lastBridgeSchemaVersion reflects response', async () => {
  mock = installMockChrome({
    nativeMessageResponse: makeNativeResponse({ bridgeSchemaVersion: 1 }),
  });
  (globalThis as any).chrome = mock;

  await sendBridgeBatch('ping');

  const stored = await new Promise<Record<string, unknown>>((resolve) => {
    chrome.storage.local.get(['bridgeState'], resolve);
  });
  const state = stored['bridgeState'] as { lastBridgeSchemaVersion: number };
  assert.equal(state.lastBridgeSchemaVersion, 1, 'Schema version should be cached after successful handshake');
});
