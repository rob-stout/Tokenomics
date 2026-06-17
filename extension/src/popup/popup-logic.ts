/**
 * Pure popup logic — no DOM, no chrome APIs, fully unit-testable.
 *
 * Responsible for merging web-fetched snapshots and Mac-bridge native
 * snapshots into a single ordered list, filtered by per-provider visibility.
 */

import type { BridgeSnapshot, ProviderVisibilitySetting } from '../bridge-types';
import type { ProviderUsageSnapshot } from '../snapshot';
import { PROVIDERS, type ProviderId } from '../types';

// Web-fetchable providers — rendered from extension-local snapshots.
// Order here drives the display order for web providers.
// geminiConsumer is content-script-driven (not a SW poll), but its snapshot
// is stored locally and bridged the same way as claude/midjourney — it belongs
// in WEB_PROVIDERS so the popup shows it with an empty state when no data yet.
// leonardo is also content-script-driven (Cognito token grab) — same pattern.
export const WEB_PROVIDERS: readonly ProviderId[] = [
  'claude',
  'codex',
  'midjourney',
  'geminiConsumer',
  'elevenlabs',
  'grok',
  'perplexity',
  'leonardo',
];

// Native-only providers — rendered from Mac-bridge snapshots only.
// Order here drives the display order for native providers (appended after web).
export const NATIVE_ONLY_PROVIDERS: readonly ProviderId[] = ['copilot', 'cursor', 'gemini'];

// Web providers whose usage the extension reads from the logged-in browser
// session. Their empty state tells the user to sign in to that site (NOT to
// install the Mac app). URLs are the hosts the readers run on (manifest
// content_scripts). Kept here next to WEB_PROVIDERS so the two stay in sync —
// the `signInCoversAllWebProviders` test enforces that every web provider is
// covered by SIGN_IN or COUNT_LOCALLY, so a new reader can't fall through to
// the wrong "install the menu bar app" fallback again.
export const SIGN_IN: Partial<Record<ProviderId, { url: string; site: string }>> = {
  claude: { url: 'https://claude.ai', site: 'claude.ai' },
  midjourney: { url: 'https://www.midjourney.com/', site: 'midjourney.com' },
  grok: { url: 'https://grok.com', site: 'grok.com' },
  perplexity: { url: 'https://www.perplexity.ai', site: 'perplexity.ai' },
  leonardo: { url: 'https://app.leonardo.ai', site: 'leonardo.ai' },
  elevenlabs: { url: 'https://elevenlabs.io', site: 'elevenlabs.io' },
  geminiConsumer: { url: 'https://gemini.google.com', site: 'gemini.google.com' },
};

// ChatGPT path is a local counter, so the empty state asks the user to open
// chatgpt.com and chat — that's what populates the counter (stored under codex).
export const COUNT_LOCALLY: Partial<Record<ProviderId, { url: string; site: string }>> = {
  codex: { url: 'https://chatgpt.com', site: 'chatgpt.com' },
};

// Gemini is tracked by the Mac app but not yet sending real snapshots (Phase 2 deferred).
// Including it here means its row will appear once the bridge sends data for it.
export type SnapshotSource = 'web' | 'native';

export interface VisibleProvider {
  providerId: ProviderId;
  source: SnapshotSource;
  /** Null when the provider is visible but has no data from either source. */
  webSnapshot: ProviderUsageSnapshot | null;
  /** Null when there is no native snapshot for this provider. */
  nativeSnapshot: BridgeSnapshot | null;
}

type WebSnapshotMap = Partial<Record<ProviderId, ProviderUsageSnapshot>>;

/**
 * Build the ordered, filtered list of providers to display in the popup.
 *
 * Resolution rules (per provider):
 * 1. If visibility[id].enabled === false, omit entirely.
 * 2. Prefer the source with the more recent capturedAt (timestamp-wins).
 * 3. If only one source has data, use that source.
 * 4. If neither source has data, include the provider with source='web'
 *    (so the web-style EmptyState is shown) for web providers, or omit
 *    native-only providers that have no data (no point showing an empty
 *    native card if the Mac hasn't sent anything).
 *
 * Ordering: web providers first (WEB_PROVIDERS order), then native-only
 * providers that have actual data or an explicit visibility entry.
 */
export function buildVisibleProviders(args: {
  visibility: Record<string, ProviderVisibilitySetting>;
  webSnapshots: WebSnapshotMap;
  nativeSnapshots: Record<string, BridgeSnapshot>;
}): VisibleProvider[] {
  const { visibility, webSnapshots, nativeSnapshots } = args;
  const result: VisibleProvider[] = [];

  // Helper: check if a provider is enabled. Default is true when no entry exists.
  function isEnabled(id: ProviderId): boolean {
    const entry = visibility[id];
    if (!entry) return true;
    return entry.enabled;
  }

  // Web providers — always included when enabled (even with no data).
  for (const id of WEB_PROVIDERS) {
    if (!isEnabled(id)) continue;

    const webSnap = webSnapshots[id] ?? null;
    const nativeSnap = nativeSnapshots[id] ?? null;

    const source = pickSource(webSnap, nativeSnap);
    result.push({ providerId: id, source, webSnapshot: webSnap, nativeSnapshot: nativeSnap });
  }

  // Native-only providers — only shown when enabled AND have native data.
  for (const id of NATIVE_ONLY_PROVIDERS) {
    if (!isEnabled(id)) continue;

    // codex is in WEB_PROVIDERS (maps to chatgpt on the web side), so skip it here.
    // The remaining native-only providers have no web reader.
    const nativeSnap = nativeSnapshots[id] ?? null;

    // For native-only providers, omit the row entirely when there is no data yet.
    // The user hasn't connected the Mac app (or the provider is disabled there).
    if (!nativeSnap) continue;

    result.push({ providerId: id, source: 'native', webSnapshot: null, nativeSnapshot: nativeSnap });
  }

  return result;
}

/**
 * Given both possible snapshots for a provider, returns whether to use the
 * web or native source. The source with the more recent capturedAt wins.
 * Web snapshot capturedAt is a millisecond epoch; native capturedAt is ISO 8601.
 */
function pickSource(
  webSnap: ProviderUsageSnapshot | null,
  nativeSnap: BridgeSnapshot | null,
): SnapshotSource {
  if (!webSnap && !nativeSnap) return 'web';
  if (!nativeSnap) return 'web';
  if (!webSnap) return 'native';

  // Compare: web capturedAt is a number (ms); native capturedAt is ISO 8601 string.
  const webMs = webSnap.capturedAt; // already a number
  const nativeMs = new Date(nativeSnap.capturedAt).getTime();

  return nativeMs > webMs ? 'native' : 'web';
}

/**
 * Convert a BridgeWindow (utilization 0-1) to the WindowUsage shape
 * (utilization 0-100) that the existing UsageBar component expects.
 * Only used at the render layer — storage shape is unchanged.
 */
export function bridgeWindowToWindowUsage(w: BridgeSnapshot['shortWindow']): {
  label: string;
  utilization: number;
  resetsAt: string;
  windowDurationSec: number;
  sublabelOverride?: string;
} {
  return {
    label: w.label,
    utilization: w.utilization * 100, // 0-1 → 0-100
    resetsAt: w.resetsAt,
    windowDurationSec: w.windowDurationSec,
    ...(w.sublabelOverride !== undefined ? { sublabelOverride: w.sublabelOverride } : {}),
  };
}

/**
 * Tells callers whether a given provider ID is web-fetchable by the extension
 * (and thus should show the web-style empty state when data is missing).
 */
export function isWebProvider(id: ProviderId): boolean {
  return (WEB_PROVIDERS as readonly string[]).includes(id);
}

// Re-export the full list for consumers that need to enumerate all known providers.
export { PROVIDERS };
