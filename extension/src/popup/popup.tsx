import { render } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import browser from 'webextension-polyfill';
import type { BridgeSnapshot, ProviderOrderSetting, ProviderVisibilitySetting } from '../bridge-types';
import type { BridgeState } from '../bridge';
import type { ExtensionMessage, ExtensionResponse } from '../messages';
import {
  computePace,
  formatTimeUntilReset,
  type ProviderUsageSnapshot,
  type UsageCredits,
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
  getSunoSnapshot,
  getUdioSnapshot,
  getPinnedProvider,
  getSelectedTab,
  grantConsent,
  hasConsent,
  setPinnedProvider,
  setSelectedTab,
} from '../storage';
import { useTextLabels } from '../label-mode';
import { applyIncomingOrder, effectiveOrder, groupByBrand, stampUserOrder } from '../provider-order';
import { type ProviderId } from '../types';
import { BridgeBanner } from './components/BridgeBanner';
import { ConsentScreen } from './components/ConsentScreen';
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
      {(snapshot.extras.scopedWeekly ?? []).map((w) => (
        <>
          <div class="usage-stack__divider" />
          <UsageBar
            isLong
            label={w.label}
            utilization={w.utilization}
            pace={computePace(w)}
            sublabel={formatTimeUntilReset(w)}
          />
        </>
      ))}
      {snapshot.extras.usageCredits ? (
        <>
          <div class="usage-stack__divider" />
          <div class="usage-bar">
            <div class="usage-bar__header">
              <span class="usage-bar__label">Usage credits</span>
              <span class="usage-bar__value">{formatCredits(snapshot.extras.usageCredits)}</span>
            </div>
          </div>
        </>
      ) : null}
    </div>
  );
}

function formatCredits(c: UsageCredits): string {
  // Intl throws on an empty/invalid currency code; fall back to a plain number.
  const validCurrency = /^[A-Z]{3}$/.test(c.currency);
  const fmt = (n: number) =>
    validCurrency
      ? new Intl.NumberFormat(undefined, { style: 'currency', currency: c.currency }).format(n)
      : n.toFixed(2);
  return c.limit !== null ? `${fmt(c.used)} of ${fmt(c.limit)}` : fmt(c.used);
}

function renderNativeBars(snap: BridgeSnapshot, showFooter = true) {
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
      {showFooter ? <NativeFooter /> : null}
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────

type WebSnapshotMap = Partial<Record<ProviderId, ProviderUsageSnapshot>>;

function UsageApp() {
  const [selected, setSelected] = useState<ProviderId>(WEB_PROVIDERS[0]);
  const [pinned, setPinned] = useState<ProviderId | null>(null);
  const [webSnapshots, setWebSnapshots] = useState<WebSnapshotMap>({});
  const [nativeSnapshots, setNativeSnapshots] = useState<Record<string, BridgeSnapshot>>({});
  const [visibility, setVisibility] = useState<Record<string, ProviderVisibilitySetting>>({});
  const [tabOrder, setTabOrder] = useState<string[] | undefined>(undefined);
  const [bridgeState, setBridgeState] = useState<BridgeState | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const textLabels = useTextLabels();

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
      getSunoSnapshot(),
      getUdioSnapshot(),
    ]).then(([claude, chatgpt, midjourney, geminiConsumer, elevenlabs, grok, perplexity, leonardo, suno, udio]) => {
      setWebSnapshots({
        ...(claude ? { claude } : {}),
        ...(chatgpt ? { chatgpt } : {}),
        ...(midjourney ? { midjourney } : {}),
        ...(geminiConsumer ? { geminiConsumer } : {}),
        ...(elevenlabs ? { elevenlabs } : {}),
        ...(grok ? { grok } : {}),
        ...(perplexity ? { perplexity } : {}),
        ...(leonardo ? { leonardo } : {}),
        ...(suno ? { suno } : {}),
        ...(udio ? { udio } : {}),
      });
    });
    void loadNativeSnapshots().then(setNativeSnapshots);
    void loadProviderVisibility().then(setVisibility);
    void browser.storage.local.get('providerOrder').then((r) => {
      setTabOrder((r['providerOrder'] as ProviderOrderSetting | undefined)?.order);
    });
    void loadBridgeState().then(setBridgeState);
    // Pull the Mac's latest (order, visibility, readings) as the popup opens; the
    // storage listeners below update the view when it lands.
    const sync: ExtensionMessage = { kind: 'SYNC_NOW' };
    void browser.runtime.sendMessage(sync).catch(() => {});
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
        setWebSnapshots((prev) => ({ ...prev, chatgpt: next ?? undefined }));
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
      if ('sunoSnapshot' in changes) {
        const next = changes['sunoSnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, suno: next ?? undefined }));
      }
      if ('udioSnapshot' in changes) {
        const next = changes['udioSnapshot']?.newValue as ProviderUsageSnapshot | undefined;
        setWebSnapshots((prev) => ({ ...prev, udio: next ?? undefined }));
      }
      if ('nativeSnapshots' in changes) {
        const next = changes['nativeSnapshots']?.newValue as Record<string, BridgeSnapshot> | undefined;
        if (next) setNativeSnapshots(next);
      }
      if ('providerVisibility' in changes) {
        const next = changes['providerVisibility']?.newValue as Record<string, ProviderVisibilitySetting> | undefined;
        if (next) setVisibility(next);
      }
      if ('providerOrder' in changes) {
        setTabOrder((changes['providerOrder']?.newValue as ProviderOrderSetting | undefined)?.order);
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
    order: tabOrder,
  });

  // Google is one tab on the Mac ("Gemini": web first, then the Gemini CLI pool).
  // When both are present, fold Google AI into the Gemini tab so the tabs match.
  const googleAI = visibleProviders.find((vp) => vp.providerId === 'gemini');
  const foldGoogle =
    googleAI !== undefined && visibleProviders.some((vp) => vp.providerId === 'geminiConsumer');
  const tabProviders = foldGoogle
    ? visibleProviders.filter((vp) => vp.providerId !== 'gemini')
    : visibleProviders;

  const visibleProviderIds: readonly ProviderId[] = tabProviders.map((vp) => vp.providerId);

  // Guard selected tab — if visibility changes remove the current tab, fall back.
  const wanted: ProviderId = foldGoogle && selected === 'gemini' ? 'geminiConsumer' : selected;
  const safeSelected: ProviderId = visibleProviderIds.includes(wanted)
    ? wanted
    : (visibleProviderIds[0] ?? WEB_PROVIDERS[0]);

  const currentEntry: VisibleProvider | undefined = visibleProviders.find(
    (vp) => vp.providerId === safeSelected,
  );

  // ── Tab handlers ───────────────────────────────────────────────
  const handleSelectTab = (provider: ProviderId) => {
    setSelected(provider);
    void setSelectedTab(provider);
  };

  // Cmd-drag on the tab bar. Only visible tabs move; hidden ones keep their slots in
  // the full order, the same "skip what isn't shown" rule the Mac sync uses.
  const handleReorder = (visibleOrder: ProviderId[], moved: ProviderId) => {
    void (async () => {
      const prev = (await browser.storage.local.get('providerOrder'))['providerOrder'] as
        | ProviderOrderSetting
        | undefined;
      // Same-brand tabs (e.g. Gemini + Google AI) travel together, matching the Mac's
      // single brand tab.
      const full = groupByBrand(
        applyIncomingOrder(visibleOrder, effectiveOrder(prev?.order)) as ProviderId[],
        moved,
      );
      await browser.storage.local.set({ providerOrder: stampUserOrder(full, prev) });
      const msg: ExtensionMessage = { kind: 'ORDER_CHANGED' };
      await browser.runtime.sendMessage(msg).catch(() => {});
    })();
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

    const googleAISnap = foldGoogle && safeSelected === 'geminiConsumer' ? googleAI?.nativeSnapshot : null;
    if (currentEntry.source === 'web' && currentWebSnap && googleAISnap) {
      // Same as the Mac's Google tab: a labelled group per pool, in the saved order.
      const order = effectiveOrder(tabOrder);
      const cliFirst = order.indexOf('gemini') < order.indexOf('geminiConsumer');
      const web = (
        <section class="pool-group">
          <div class="pool-group__header">Gemini (app)</div>
          {renderUsageBars(currentWebSnap)}
        </section>
      );
      const cli = (
        <section class="pool-group">
          <div class="pool-group__header">Gemini CLI</div>
          {renderNativeBars(googleAISnap)}
        </section>
      );
      return (
        <div class="pool-groups">
          {cliFirst ? cli : web}
          {cliFirst ? web : cli}
        </div>
      );
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
        textLabels={textLabels}
        onReorder={handleReorder}
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

/** Shows the consent screen until the user agrees, then the usage popup. */
function App() {
  // null while the stored answer loads — render nothing rather than flash.
  const [consented, setConsented] = useState<boolean | null>(null);

  useEffect(() => {
    void hasConsent().then(setConsented);
  }, []);

  const handleAgree = async () => {
    await grantConsent();
    const message: ExtensionMessage = { kind: 'CONSENT_GRANTED' };
    await browser.runtime.sendMessage(message).catch(() => undefined);
    setConsented(true);
  };

  if (consented === null) return null;
  if (!consented) {
    return (
      <div class="popup">
        <ConsentScreen onAgree={() => void handleAgree()} />
      </div>
    );
  }
  return <UsageApp />;
}

const root = document.getElementById('app');
if (root) render(<App />, root);
