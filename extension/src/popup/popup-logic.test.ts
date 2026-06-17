/**
 * Unit tests for popup-logic.ts — buildVisibleProviders and helpers.
 *
 * Run via `npm run test`.
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
  buildVisibleProviders,
  bridgeWindowToWindowUsage,
  WEB_PROVIDERS,
  NATIVE_ONLY_PROVIDERS,
  SIGN_IN,
  COUNT_LOCALLY,
} from './popup-logic';
import type { BridgeSnapshot } from '../bridge-types';
import type { ProviderUsageSnapshot } from '../snapshot';

// ── Empty-state coverage guard ───────────────────────────────────
// Every web provider must have an empty-state path that points at the BROWSER
// (SIGN_IN) or the local-counter site (COUNT_LOCALLY). Without this, a newly
// added web reader silently falls through to the wrong "install the menu bar
// app" fallback in EmptyState — the bug that hid Grok/ElevenLabs/Gemini/Leonardo.
test('signInCoversAllWebProviders: every web provider has a web empty state', () => {
  const missing = WEB_PROVIDERS.filter(
    (id) => SIGN_IN[id] === undefined && COUNT_LOCALLY[id] === undefined,
  );
  assert.deepEqual(
    missing,
    [],
    `Web providers missing a SIGN_IN/COUNT_LOCALLY entry (they'd wrongly show "install the menu bar app"): ${missing.join(', ')}`,
  );
});

// ── Helpers ──────────────────────────────────────────────────────

function makeWebSnapshot(provider: string, capturedAtMs: number): ProviderUsageSnapshot {
  return {
    provider: provider as ProviderUsageSnapshot['provider'],
    shortWindow: {
      label: '5h',
      utilization: 50,
      resetsAt: '2026-05-14T23:00:00.000Z',
      windowDurationSec: 18000,
    },
    longWindow: null,
    extras: {},
    planLabel: 'Pro',
    capturedAt: capturedAtMs,
    estimated: false,
  };
}

function makeNativeSnapshot(provider: string, capturedAtISO: string): BridgeSnapshot {
  return {
    provider,
    capturedAt: capturedAtISO,
    shortWindow: {
      label: '5h',
      utilization: 0.6,
      resetsAt: '2026-05-14T23:00:00.000Z',
      windowDurationSec: 18000,
    },
    longWindow: null,
    planLabel: 'Business',
  };
}

// ── Test 1: timestamp resolution — native wins when newer ────────

test('buildVisibleProviders: native snapshot wins when capturedAt is later than web', () => {
  const T0_ms = 1_747_248_000_000; // earlier
  const T1_iso = '2026-05-14T19:00:00.000Z'; // later (1_747_252_800_000 ms)

  const webSnap = makeWebSnapshot('claude', T0_ms);
  const nativeSnap = makeNativeSnapshot('claude', T1_iso);

  const result = buildVisibleProviders({
    visibility: {},
    webSnapshots: { claude: webSnap },
    nativeSnapshots: { claude: nativeSnap },
  });

  const claudeEntry = result.find((e) => e.providerId === 'claude');
  assert.ok(claudeEntry, 'claude entry should be present');
  assert.equal(claudeEntry.source, 'native', 'native should win when its capturedAt is later');
  assert.equal(claudeEntry.nativeSnapshot, nativeSnap);
  assert.equal(claudeEntry.webSnapshot, webSnap);
});

// ── Test 2: timestamp resolution — web wins when newer ──────────

test('buildVisibleProviders: web snapshot wins when capturedAt is later than native', () => {
  const T0_iso = '2026-05-14T17:00:00.000Z'; // earlier  (1778778000000 ms)
  const T1_ms = 1_778_788_800_000; // 2026-05-14T20:00:00Z — later

  const webSnap = makeWebSnapshot('claude', T1_ms);
  const nativeSnap = makeNativeSnapshot('claude', T0_iso);

  const result = buildVisibleProviders({
    visibility: {},
    webSnapshots: { claude: webSnap },
    nativeSnapshots: { claude: nativeSnap },
  });

  const claudeEntry = result.find((e) => e.providerId === 'claude');
  assert.ok(claudeEntry, 'claude entry should be present');
  assert.equal(claudeEntry.source, 'web', 'web should win when its capturedAt is later');
});

// ── Test 3: visibility map — disabled provider omitted ──────────

test('buildVisibleProviders: provider with enabled=false is omitted', () => {
  const result = buildVisibleProviders({
    visibility: {
      midjourney: { enabled: false, lastChangedAt: '2026-05-14T18:00:00.000Z' },
    },
    webSnapshots: { midjourney: makeWebSnapshot('midjourney', Date.now()) },
    nativeSnapshots: {},
  });

  const mjEntry = result.find((e) => e.providerId === 'midjourney');
  assert.equal(mjEntry, undefined, 'disabled provider should be omitted from the list');
});

// ── Test 4: empty-state for visible-but-no-data web providers ───

test('buildVisibleProviders: visible web provider with no data appears with snapshot=null', () => {
  const result = buildVisibleProviders({
    visibility: {
      claude: { enabled: true, lastChangedAt: '2026-05-14T18:00:00.000Z' },
    },
    webSnapshots: {}, // no data
    nativeSnapshots: {},
  });

  const claudeEntry = result.find((e) => e.providerId === 'claude');
  assert.ok(claudeEntry, 'claude entry should be present even with no data');
  assert.equal(claudeEntry.webSnapshot, null, 'webSnapshot should be null when no data');
  assert.equal(claudeEntry.nativeSnapshot, null, 'nativeSnapshot should be null when no data');
  assert.equal(claudeEntry.source, 'web', 'source defaults to web for web providers with no data');
});

// ── Test 5: native-only provider absent when no native data ─────

test('buildVisibleProviders: native-only provider with no data is omitted', () => {
  const result = buildVisibleProviders({
    visibility: {
      copilot: { enabled: true, lastChangedAt: '2026-05-14T18:00:00.000Z' },
    },
    webSnapshots: {},
    nativeSnapshots: {}, // no copilot data from bridge
  });

  const copilotEntry = result.find((e) => e.providerId === 'copilot');
  assert.equal(copilotEntry, undefined, 'native-only provider with no data should be omitted');
});

// ── Test 6: native-only provider present when bridge has data ───

test('buildVisibleProviders: native-only provider appears when bridge has data', () => {
  const result = buildVisibleProviders({
    visibility: {},
    webSnapshots: {},
    nativeSnapshots: {
      copilot: makeNativeSnapshot('copilot', '2026-05-14T18:00:00.000Z'),
    },
  });

  const copilotEntry = result.find((e) => e.providerId === 'copilot');
  assert.ok(copilotEntry, 'copilot entry should appear when bridge provides data');
  assert.equal(copilotEntry.source, 'native');
});

// ── Test 7: ordering — web providers before native-only ─────────

test('buildVisibleProviders: web providers appear before native-only providers', () => {
  const result = buildVisibleProviders({
    visibility: {},
    webSnapshots: {
      claude: makeWebSnapshot('claude', Date.now()),
      midjourney: makeWebSnapshot('midjourney', Date.now()),
    },
    nativeSnapshots: {
      copilot: makeNativeSnapshot('copilot', '2026-05-14T18:00:00.000Z'),
      cursor: makeNativeSnapshot('cursor', '2026-05-14T18:00:00.000Z'),
    },
  });

  const ids = result.map((e) => e.providerId);
  const idStrings = ids as readonly string[];
  const webIds = (WEB_PROVIDERS as readonly string[]).filter((id) => idStrings.includes(id));
  const nativeIds = (NATIVE_ONLY_PROVIDERS as readonly string[]).filter((id) => idStrings.includes(id));

  // All web providers must appear before any native-only provider.
  const lastWebIndex = Math.max(...webIds.map((id) => idStrings.indexOf(id)));
  const firstNativeIndex = Math.min(...nativeIds.map((id) => idStrings.indexOf(id)));

  assert.ok(
    lastWebIndex < firstNativeIndex,
    `Web providers (last at ${lastWebIndex}) must precede native providers (first at ${firstNativeIndex})`,
  );
});

// ── Test 8: bridgeWindowToWindowUsage multiplies utilization ────

test('bridgeWindowToWindowUsage: converts 0-1 utilization to 0-100', () => {
  const bridgeWindow = {
    label: '5h',
    utilization: 0.42,
    resetsAt: '2026-05-14T23:00:00.000Z',
    windowDurationSec: 18000,
  };

  const result = bridgeWindowToWindowUsage(bridgeWindow);
  assert.ok(
    Math.abs(result.utilization - 42) < 0.01,
    `Expected ~42, got ${result.utilization}`,
  );
  assert.equal(result.label, bridgeWindow.label);
  assert.equal(result.resetsAt, bridgeWindow.resetsAt);
  assert.equal(result.windowDurationSec, bridgeWindow.windowDurationSec);
});
