import { render } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import browser from 'webextension-polyfill';
import type { BridgeSnapshot, ProviderVisibilitySetting } from '../bridge-types';
import type { BridgeState } from '../bridge';
import type { ExtensionMessage, ExtensionResponse } from '../messages';
import {
  computePace,
  formatTimeUntilReset,
  type ProviderUsageSnapshot,
  type WindowUsage,
} from '../snapshot';
import {
  getChatGPTSnapshot,
  getClaudeSnapshot,
  getGeminiConsumerSnapshot,
  getMidjourneySnapshot,
  getElevenLabsSnapshot,
  getGrokSnapshot,
  getPerplexitySnapshot,
  getLeonardoSnapshot,
  getPinnedProvider,
  getSelectedTab,
  setPinnedProvider,
  setSelectedTab,
} from '../storage';
import { type ProviderId } from '../types';
import { BridgeBanner } from './components/BridgeBanner';
import { EmptyState } from './components/EmptyState';
import { Header } from './components/Header';
import { NativeFooter } from './components/NativeFooter';
import { ProviderTabBar } from './components/ProviderTabBar';
import { SyncFooter } from './components/SyncFooter';
import { UsageBar } from './components/UsageBar';
import {
  buildVisibleProviders,
  bridgeWindowToWindowUsage,
  WEB_PROVIDERS,
  type VisibleProvider,
} from './popup-logic';

// ── Theme ─────────────────────────────────────────────────────────

function applyTheme() {
  const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  document.documentElement.dataset.theme = isDark ? 'dark' : 'light';
}

// ── Storage helpers ───────────────────────────────────────────────

async function loadNativeSnapshots(): Promise<Record<string, BridgeSnapshot>> {
  const result = await browser.storage.local.get('nativeSnapshots');
  const raw = result['nativeSnapshots'];
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    return raw as Record<string, BridgeSnapshot>;
  }
  return {};
}

async function loadProviderVisibility(): Promise<Record<string, ProviderVisibilitySetting>> {
  const result = await browser.storage.local.get('providerVisibility');
  const raw = result['providerVisibility'];
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    return raw as Record<string, ProviderVisibilitySetting>;
  }
  return {};
}

async function loadBridgeState(): Promise<BridgeState | null> {
  const result = await browser.storage.local.get('bridgeState');
  const raw = result['bridgeState'];
  if (raw && typeof raw === 'object') return raw as BridgeState;
  return null;
}

// ── Snapshot rendering ────────────────────────────────────────────

function renderUsageBars(snapshot: ProviderUsageSnapshot) {
  const short = snapshot.shortWindow;
  const long = snapshot.longWindow;
  return (
    <div class="usage-stack">
      <UsageBar
        label={short.label}
        utilization={short.utilization}
        pace={computePace(short)}
        sublabel={formatTimeUntilReset(short)}
      />
      {long ? (
        <>
          <div class="usage-stack__divider" />
          <UsageBar
            isLong
            label={long.label}
            utilization={long.utilization}
            pace={computePace(long)}
            sublabel={formatTimeUntilReset(long)}
          />
        </>
      ) : null}
    </div>
  );
}

function renderNativeBars(snap: BridgeSnapshot) {
  const short: WindowUsage = bridgeWindowToWindowUsage(snap.shortWindow);
  const long: WindowUsage | null = snap.longWindow
    ? bridgeWindowToWindowUsage(snap.longWindow)
    : null;
  return (
    <div class="usage-stack">
      <UsageBar
        label={short.label}
        utilization={short.utilization}
        pace={computePace(short)}
        sublabel={formatTimeUntilReset(short)}
      />
      {long ? (
        <>
          <div class="usage-stack__divider" />
          <UsageBar
            isLong
            label={long.label}
            utilization={long.utilization}
            pace={computePace(long)}
            sublabel={formatTimeUntilReset(long)}
          />
        </>
      ) : null}
      <NativeFooter />
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────

type WebSnapshotMap = Partial<Record<ProviderId, ProviderUsageSnapshot>>;

function App() {
  const [selected, setSelected] = useState<ProviderId>(WEB_PROVIDERS[0]);
  const [pinned, setPinned] = useState<ProviderId | null>(null);
  const [webSnapshots, setWebSnapshots] = useState<WebSnapshotMap>({});
  const [nativeSnapshots, setNativeSnapshots] = useState<Record<string, BridgeSnapshot>>({});
  const [visibility, setVisibility] = useState<Record<string, ProviderVisibilitySetting>>({});
  const [bridgeState, setBridgeState] = useState<BridgeState | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  // ── Initial load from storage ──────────────────────────────────
  useEffect(() => {
    void getSelectedTab().then((stored) => {
      if (stored) setSelected(stored);
    });
    void getPinnedProvider().then(setPinned);
    void Promise.all([
      getClaudeSnapshot(),
      getChatGPTSnapshot(),
      getMidjourneySnapshot(),
      getGeminiConsumerSnapshot(),
      getElevenLabsSnapshot(),
      getGrokSnapshot(),
      getPerplexitySnapshot(),
      getLeonardoSnapshot(),
    ]).then(([claude, chatgpt, midjourney, geminiConsumer, elevenlabs, grok, perplexity, leonardo]) => {
      setWebSnapshots({
        ...(claude ? { claude } : {}),
        ...(chatgpt ? { codex: chatgpt } : {}),
        ...(midjourney ? { midjourney } : {}),
        ...(geminiConsumer ? { geminiConsumer } : {}),
        ...(elevenlabs ? { elevenlabs } : {}),
        ...(grok ? { grok } : {}),
        ...(perplexity ? { perplexity } : {}),
        ...(leonardo ? { leonardo } : {}),
      });
    });
    void loadNativeSnapshots().then(setNativeSnapshots);
    void loadProviderVisibility().then(setVisibility);
    void loadBridgeState().then(setBridgeState);
  }, []);

  // ── Live storage updates ───────────────────────────────────────
  useEffect(() => {
    const handler = (
      changes: Record<string, browser.Storage.StorageChange>,
      area: string,
    ) => {
      if (area !== 'local') return;

      if ('claudeSnapshot' in changes) {
        const next = changes['claudeSnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, claude: next ?? undefined }));
      }
      if ('chatgptSnapshot' in changes) {
        const next = changes['chatgptSnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, codex: next ?? undefined }));
      }
      if ('midjourneySnapshot' in changes) {
        const next = changes['midjourneySnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, midjourney: next ?? undefined }));
      }
      if ('geminiConsumerSnapshot' in changes) {
        const next = changes['geminiConsumerSnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, geminiConsumer: next ?? undefined }));
      }
      if ('elevenLabsSnapshot' in changes) {
        const next = changes['elevenLabsSnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, elevenlabs: next ?? undefined }));
      }
      if ('grokSnapshot' in changes) {
        const next = changes['grokSnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, grok: next ?? undefined }));
      }
      if ('perplexitySnapshot' in changes) {
        const next = changes['perplexitySnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, perplexity: next ?? undefined }));
      }
      if ('leonardoSnapshot' in changes) {
        const next = changes['leonardoSnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, leonardo: next ?? undefined }));
      }
      if ('nativeSnapshots' in changes) {
        const next = changes['nativeSnapshots']?.newValue as Record<string, BridgeSnapshot> | undefined;
        if (next) setNativeSnapshots(next);
      }
      if ('providerVisibility' in changes) {
        const next = changes['providerVisibility']?.newValue as Record<string, ProviderVisibilitySetting> | undefined;
        if (next) setVisibility(next);
      }
      if ('bridgeState' in changes) {
        const next = changes['bridgeState']?.newValue as BridgeState | undefined;
        if (next) setBridgeState(next);
      }
    };

    browser.storage.onChanged.addListener(handler);
    return () => browser.storage.onChanged.removeListener(handler);
  }, []);

  // ── Derived provider list ──────────────────────────────────────
  const visibleProviders = buildVisibleProviders({
    visibility,
    webSnapshots,
    nativeSnapshots,
  });

  const visibleProviderIds: readonly ProviderId[] = visibleProviders.map((vp) => vp.providerId);

  // Guard selected tab — if visibility changes remove the current tab, fall back.
  const safeSelected: ProviderId = visibleProviderIds.includes(selected)
    ? selected
    : (visibleProviderIds[0] ?? WEB_PROVIDERS[0]);

  const currentEntry: VisibleProvider | undefined = visibleProviders.find(
    (vp) => vp.providerId === safeSelected,
  );

  // ── Tab handlers ───────────────────────────────────────────────
  const handleSelectTab = (provider: ProviderId) => {
    setSelected(provider);
    void setSelectedTab(provider);
  };

  const handleSetSmart = () => {
    setPinned(null);
    void setPinnedProvider(null);
  };

  const handleTogglePin = (provider: ProviderId) => {
    const next = pinned === provider ? null : provider;
    setPinned(next);
    void setPinnedProvider(next);
  };

  // ── Refresh handler ────────────────────────────────────────────
  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      const message: ExtensionMessage = { kind: 'REFRESH_REQUESTED' };
      const response = (await browser.runtime.sendMessage(message)) as
        | ExtensionResponse
        | undefined;
      if (response?.kind === 'REFRESH_FAILED') {
        console.warn('[tokenomics] refresh failed:', response.error);
      } else if (response?.kind === 'REFRESH_BACKOFF') {
        console.warn('[tokenomics] refresh skipped, rate limited until', new Date(response.until));
      }
    } catch (err) {
      console.warn('[tokenomics] refresh dispatch failed', err);
    } finally {
      setIsRefreshing(false);
    }
  };

  const handleSettings = () => {
    void browser.runtime.openOptionsPage();
  };

  // ── Header meta — derived from the selected provider's snapshot ─
  const currentWebSnap = currentEntry?.webSnapshot ?? null;
  const currentNativeSnap = currentEntry?.nativeSnapshot ?? null;
  const useNative = currentEntry?.source === 'native' && currentNativeSnap !== null;

  const planLabel = useNative
    ? (currentNativeSnap?.planLabel ?? undefined)
    : (currentWebSnap?.planLabel ?? undefined);
  const estimated = !useNative && currentWebSnap?.estimated === true;

  const lastSynced: Date | null = useNative && currentNativeSnap
    ? new Date(currentNativeSnap.capturedAt)
    : currentWebSnap
      ? new Date(currentWebSnap.capturedAt)
      : null;

  // ── Render body ────────────────────────────────────────────────
  function renderBody() {
    if (!currentEntry) {
      return <EmptyState provider={safeSelected} />;
    }

    if (currentEntry.source === 'native' && currentNativeSnap) {
      return renderNativeBars(currentNativeSnap);
    }

    if (currentEntry.source === 'web' && currentWebSnap) {
      return renderUsageBars(currentWebSnap);
    }

    // No data from either source.
    return (
      <EmptyState
        provider={safeSelected}
        isNativeSource={currentEntry.source === 'native'}
      />
    );
  }

  return (
    <div class="popup">
      <Header planLabel={planLabel} estimated={estimated} />

      <BridgeBanner bridgeState={bridgeState} />

      <ProviderTabBar
        selected={safeSelected}
        visibleProviderIds={visibleProviderIds}
        onSelect={handleSelectTab}
      />

      <main class="popup__body">{renderBody()}</main>

      <SyncFooter
        lastSynced={lastSynced}
        isLoading={isRefreshing}
        onRefresh={handleRefresh}
        onSettings={handleSettings}
        visibleProviders={visibleProviderIds}
        pinnedProvider={pinned}
        onSetSmart={handleSetSmart}
        onTogglePin={handleTogglePin}
      />
    </div>
  );
}

applyTheme();
window
  .matchMedia('(prefers-color-scheme: dark)')
  .addEventListener('change', applyTheme);

const root = document.getElementById('app');
if (root) render(<App />, root);
