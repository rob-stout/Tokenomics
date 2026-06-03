/**
 * Native Messaging Host bridge — sends batched provider snapshots and settings
 * to the TokenomicsBridge Mac helper, and merges its response back into local
 * chrome.storage.local.
 *
 * Storage keys owned by this module:
 *   bridgeState              — BridgeState object (lastSuccessAt, schema/app version, status ring)
 *   bridgeStatus             — BridgeStatusEntry[] ring buffer, cap 50 (convenience alias for
 *                              bridgeState.status; kept flat so the options page can read it cheaply)
 *   nativeSnapshots          — Record<string, BridgeSnapshot> — Mac-side provider snapshots,
 *                              keyed by provider id, last-capturedAt-wins.
 *   pendingRequestedActions  — Partial<{ refreshNativeProviders: boolean }> — written by the popup
 *                              or options page when the user requests a native refresh; cleared here
 *                              after being included in the next outbound envelope.
 *   providerVisibility       — Record<string, ProviderVisibilitySetting> — per-provider enabled
 *                              flag + lastChangedAt; merged with the Mac side on every round trip.
 */

import {
  BRIDGE_HOST_NAME,
  BRIDGE_SCHEMA_VERSION,
  type BridgeRequest,
  type BridgeResponse,
  type BridgeSnapshot,
  type BridgeWindow,
  type ProviderVisibilitySetting,
} from './bridge-types';
import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

// Storage keys for provider snapshots — must stay in sync with storage.ts KEYS.
// Every web reader's storage key. Keep in sync with storage.ts KEYS. The bridge
// gather iterates ALL of these so a new reader is transmitted automatically — the
// old hard-coded 3-key list silently dropped geminiConsumer/grok/perplexity/
// leonardo (computed + badged but never sent to the Mac).
//
// elevenlabs is intentionally omitted: the Mac reads it via API key, so we don't
// override that with the web reading (yet).
const SNAPSHOT_KEYS = {
  claude: 'claudeSnapshot',
  chatgpt: 'chatgptSnapshot',
  geminiConsumer: 'geminiConsumerSnapshot',
  midjourney: 'midjourneySnapshot',
  grok: 'grokSnapshot',
  perplexity: 'perplexitySnapshot',
  leonardo: 'leonardoSnapshot',
} as const;

// ── Command handler registry ─────────────────────────────────────
// background.ts registers handlers on boot to avoid a circular import.

let refreshWebProvidersHandler: (() => void) | null = null;

/**
 * Register the handler that will be called when the Mac app sends a
 * "refreshWebProviders" command. background.ts calls this on SW boot so
 * bridge.ts never needs to import background.ts directly.
 */
export function registerRefreshWebProvidersHandler(handler: () => void): void {
  refreshWebProvidersHandler = handler;
}

// ── Public types ─────────────────────────────────────────────────

export interface BridgeStatusEntry {
  ts: number;
  level: 'ok' | 'warn' | 'error';
  message: string;
}

export interface BridgeState {
  lastSuccessAt: number | null;
  lastBridgeSchemaVersion: number | null;
  lastMacAppVersion: string | null;
  /** Ring buffer, capped at BRIDGE_STATUS_CAP entries. */
  status: BridgeStatusEntry[];
}

export type BridgeSendReason = 'snapshot' | 'heartbeat' | 'settings' | 'ping';

// ── Internal state ───────────────────────────────────────────────

const BRIDGE_STATUS_CAP = 50;

/** In-flight promise for the current sendNativeMessage call. */
let inFlightPromise: Promise<BridgeResponse | null> | null = null;

/** Debounce timer handle for scheduleBridgeSend. */
let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let pendingReason: BridgeSendReason = 'snapshot';

// ── Storage helpers (callback → promise) ─────────────────────────

function storageGet(keys: string[]): Promise<Record<string, unknown>> {
  return new Promise((resolve) => {
    chrome.storage.local.get(keys, (items) => resolve(items));
  });
}

function storageSet(items: Record<string, unknown>): Promise<void> {
  return new Promise((resolve) => {
    chrome.storage.local.set(items, () => resolve());
  });
}

// ── Wire translation ─────────────────────────────────────────────

/**
 * Converts a WindowUsage (utilization 0-100) to a BridgeWindow (utilization 0-1).
 */
function toBridgeWindow(w: WindowUsage): BridgeWindow {
  return {
    label: w.label,
    utilization: w.utilization / 100,
    resetsAt: w.resetsAt,
    windowDurationSec: w.windowDurationSec,
    ...(w.sublabelOverride !== undefined ? { sublabelOverride: w.sublabelOverride } : {}),
  };
}

/**
 * Converts a ProviderUsageSnapshot (capturedAt as ms epoch, utilization 0-100)
 * to a BridgeSnapshot (capturedAt as ISO 8601, utilization 0-1).
 */
function toBridgeSnapshot(snap: ProviderUsageSnapshot): BridgeSnapshot {
  return {
    provider: snap.provider,
    capturedAt: new Date(snap.capturedAt).toISOString(),
    ...(snap.estimated !== undefined ? { estimated: snap.estimated } : {}),
    shortWindow: toBridgeWindow(snap.shortWindow),
    longWindow: snap.longWindow ? toBridgeWindow(snap.longWindow) : null,
    planLabel: snap.planLabel,
  };
}

// ── Bridge status helpers ────────────────────────────────────────

function appendStatus(
  existing: BridgeStatusEntry[],
  level: BridgeStatusEntry['level'],
  message: string,
): BridgeStatusEntry[] {
  const entry: BridgeStatusEntry = { ts: Date.now(), level, message };
  const next = [...existing, entry];
  return next.length > BRIDGE_STATUS_CAP ? next.slice(next.length - BRIDGE_STATUS_CAP) : next;
}

async function loadBridgeState(): Promise<BridgeState> {
  const result = await storageGet(['bridgeState']);
  const raw = result['bridgeState'];
  if (raw && typeof raw === 'object') return raw as BridgeState;
  return { lastSuccessAt: null, lastBridgeSchemaVersion: null, lastMacAppVersion: null, status: [] };
}

async function saveBridgeState(state: BridgeState): Promise<void> {
  await storageSet({ bridgeState: state, bridgeStatus: state.status });
}

// ── Merge helpers ────────────────────────────────────────────────

/**
 * Merges two providerVisibility maps. Per provider, the entry with the later
 * lastChangedAt wins. Returns a new merged map.
 */
function mergeVisibility(
  local: Record<string, ProviderVisibilitySetting>,
  incoming: Record<string, ProviderVisibilitySetting>,
): Record<string, ProviderVisibilitySetting> {
  const merged: Record<string, ProviderVisibilitySetting> = { ...local };
  for (const [id, incomingSetting] of Object.entries(incoming)) {
    const localSetting = merged[id];
    if (!localSetting || incomingSetting.lastChangedAt > localSetting.lastChangedAt) {
      merged[id] = incomingSetting;
    }
  }
  return merged;
}

/**
 * Merges incoming nativeSnapshots into the existing map. Per provider,
 * the entry with the later capturedAt wins.
 */
function mergeNativeSnapshots(
  existing: Record<string, BridgeSnapshot>,
  incoming: BridgeSnapshot[],
): Record<string, BridgeSnapshot> {
  const merged: Record<string, BridgeSnapshot> = { ...existing };
  for (const snap of incoming) {
    const current = merged[snap.provider];
    if (!current || snap.capturedAt > current.capturedAt) {
      merged[snap.provider] = snap;
    }
  }
  return merged;
}

// ── Core send ────────────────────────────────────────────────────

async function doSend(_reason: BridgeSendReason): Promise<BridgeResponse | null> {
  // 1. Gather provider snapshots directly from chrome.storage.local (avoids
  //    pulling in webextension-polyfill — storage.ts owns those reads in prod,
  //    but bridge.ts must stay polyfill-free for test compatibility).
  const allSnapshotKeys = Object.values(SNAPSHOT_KEYS);
  const snapshotResult = await storageGet(allSnapshotKeys);

  function parseSnap(raw: unknown): ProviderUsageSnapshot | null {
    if (!raw || typeof raw !== 'object') return null;
    return raw as ProviderUsageSnapshot;
  }

  // Transmit every present web-reader snapshot. Iterating the key set (rather
  // than naming each) means a newly-added reader ships without a code change here.
  const snapshots: BridgeSnapshot[] = [];
  for (const key of allSnapshotKeys) {
    const snap = parseSnap(snapshotResult[key]);
    if (snap) snapshots.push(toBridgeSnapshot(snap));
  }

  // 2. Gather settings and pending actions from storage
  const stored = await storageGet(['providerVisibility', 'pendingRequestedActions', 'nativeSnapshots']);
  const providerVisibility = (stored['providerVisibility'] as Record<string, ProviderVisibilitySetting>) ?? {};
  const requestedActions = (stored['pendingRequestedActions'] as Record<string, boolean>) ?? {};
  const existingNativeSnapshots = (stored['nativeSnapshots'] as Record<string, BridgeSnapshot>) ?? {};

  // Clear pending actions before the send so we don't double-deliver on retry
  await storageSet({ pendingRequestedActions: {} });

  // 3. Build the request envelope
  const request: BridgeRequest = {
    schemaVersion: BRIDGE_SCHEMA_VERSION,
    envelopeSentAt: new Date().toISOString(),
    extensionId: chrome.runtime.id,
    snapshots,
    settings: { providerVisibility },
    requestedActions: Object.keys(requestedActions).length > 0 ? requestedActions : undefined,
  };

  // 4. Send over NMH (callback → promise)
  const response = await new Promise<BridgeResponse | null>((resolve) => {
    chrome.runtime.sendNativeMessage(BRIDGE_HOST_NAME, request, (raw: unknown) => {
      if (chrome.runtime.lastError) {
        resolve(null);
        return;
      }
      resolve(raw as BridgeResponse);
    });
  });

  // 5. Load current bridge state for mutation
  const state = await loadBridgeState();

  if (response === null) {
    // Error path — append status entry
    const errMsg = 'sendNativeMessage failed: ' + (chrome.runtime.lastError?.message ?? 'unknown error');
    state.status = appendStatus(state.status, 'error', errMsg);
    // Only blank lastSuccessAt when the host is entirely absent
    if (chrome.runtime.lastError?.message?.includes('host not found')) {
      state.lastSuccessAt = null;
    }
    await saveBridgeState(state);
    return null;
  }

  // 6. Process successful response
  // Merge nativeSnapshots
  const mergedNative = mergeNativeSnapshots(existingNativeSnapshots, response.nativeSnapshots ?? []);
  await storageSet({ nativeSnapshots: mergedNative });

  // Merge providerVisibility
  const responseVisibility = response.settings?.providerVisibility ?? {};
  const mergedVisibility = mergeVisibility(providerVisibility, responseVisibility);
  await storageSet({ providerVisibility: mergedVisibility });

  // Dispatch commands
  for (const cmd of response.commands ?? []) {
    if (cmd.kind === 'refreshWebProviders') {
      if (refreshWebProvidersHandler) {
        refreshWebProvidersHandler();
      }
    } else {
      state.status = appendStatus(state.status, 'warn', `Unknown bridge command: ${cmd.kind}`);
    }
  }

  // Update state on success
  state.lastSuccessAt = Date.now();
  state.lastBridgeSchemaVersion = response.bridgeSchemaVersion ?? null;
  state.lastMacAppVersion = response.macAppVersion ?? null;
  state.status = appendStatus(state.status, 'ok', `Bridge ok — Mac app ${response.macAppVersion}`);
  await saveBridgeState(state);

  return response;
}

// ── Public API ───────────────────────────────────────────────────

/**
 * Force-flush whatever local state is pending. If a call is already in flight,
 * all concurrent callers await that same underlying promise (single-flight).
 */
export function sendBridgeBatch(reason: BridgeSendReason): Promise<BridgeResponse | null> {
  if (inFlightPromise !== null) {
    return inFlightPromise;
  }
  inFlightPromise = doSend(reason).finally(() => {
    inFlightPromise = null;
  });
  return inFlightPromise;
}

/**
 * Schedule a debounced send (500ms). Multiple calls within the window coalesce
 * into one sendBridgeBatch at the end of the window. Called after each
 * provider snapshot write.
 */
export function scheduleBridgeSend(reason: BridgeSendReason): void {
  // Keep the highest-priority reason if called multiple times before flush
  pendingReason = reason;
  if (debounceTimer !== null) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    debounceTimer = null;
    void sendBridgeBatch(pendingReason);
  }, 500);
}
