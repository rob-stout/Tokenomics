import { render } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import browser from 'webextension-polyfill';
import type { ExtensionMessage, ExtensionResponse } from '../messages';
import type { ChatGPTPlan } from '../chatgpt';
import type { ProviderOrderSetting, ProviderVisibilitySetting } from '../bridge-types';
import {
  getApiKey,
  getChatGPTPlanAuto,
  getChatGPTPlanOverride,
  getShowSiteNames,
  grantConsent,
  hasConsent,
  revokeConsentAndClear,
  setShowSiteNames,
} from '../storage';
import { useTextLabels } from '../label-mode';
import { TEXT_LABELS_ONLY } from '../labels';
import { ConsentScreen } from '../popup/components/ConsentScreen';
import { PROVIDER_META, type ProviderId } from '../types';
import { effectiveOrder, moveInOrder, moveToPosition } from '../provider-order';
import { TRYTOKENOMICS_URL } from '../urls';
import { applyOrderChange, applyVisibilityToggle } from './options-logic';

// ── Theme ────────────────────────────────────────────

function applyTheme() {
  const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  document.documentElement.dataset.theme = isDark ? 'dark' : 'light';
}

// ── Types ────────────────────────────────────────────

/**
 * The value stored/sent. 'auto' means "clear the override".
 * Must match the CHATGPT_SET_PLAN message union — 'unknown' is intentionally
 * excluded because users cannot meaningfully choose it.
 */
type PlanChoice = 'auto' | 'free' | 'plus' | 'pro' | 'team';

interface RadioOption {
  value: PlanChoice;
  label: string;
  helper: string;
}

// ── Storage helpers ──────────────────────────────────

async function loadVisibility(): Promise<Record<string, ProviderVisibilitySetting>> {
  const result = await browser.storage.local.get('providerVisibility');
  const raw = result['providerVisibility'];
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    return raw as Record<string, ProviderVisibilitySetting>;
  }
  return {};
}

async function saveVisibility(map: Record<string, ProviderVisibilitySetting>): Promise<void> {
  await browser.storage.local.set({ providerVisibility: map });
}

async function loadOrder(): Promise<ProviderOrderSetting | undefined> {
  const result = await browser.storage.local.get('providerOrder');
  const raw = result['providerOrder'];
  return raw && typeof raw === 'object' && Array.isArray((raw as ProviderOrderSetting).order)
    ? (raw as ProviderOrderSetting)
    : undefined;
}

async function saveOrder(setting: ProviderOrderSetting): Promise<void> {
  await browser.storage.local.set({ providerOrder: setting });
}

// ── Visibility storage setter (browser-polyfill-aware) ────────────

const browserSaveVisibility = saveVisibility;

// ── Helpers ──────────────────────────────────────────

function planDisplayName(plan: ChatGPTPlan): string {
  switch (plan) {
    case 'free': return 'Free';
    case 'plus': return 'Plus';
    case 'pro': return 'Pro';
    case 'team': return 'Team';
    case 'unknown': return 'Unknown';
  }
}

function buildOptions(autoPlan: ChatGPTPlan): RadioOption[] {
  const autoLabel =
    autoPlan !== 'unknown'
      ? `Auto-detect (currently: ${planDisplayName(autoPlan)})`
      : 'Auto-detect (plan not yet detected)';

  return [
    {
      value: 'auto',
      label: autoLabel,
      helper: 'Tokenomics reads your plan from the ChatGPT session automatically.',
    },
    {
      value: 'free',
      label: 'Free',
      helper: '10 messages / 5-hour window.',
    },
    {
      value: 'plus',
      label: 'Plus',
      helper: '160 messages / 3-hour window · 3,000 Thinking messages / week.',
    },
    {
      value: 'pro',
      label: 'Pro',
      helper: 'Effectively uncapped on GPT-5.x · 15,000 Thinking messages / week.',
    },
    {
      value: 'team',
      label: 'Team',
      helper: '160 messages / 3-hour window · 3,000 Thinking messages / week.',
    },
  ];
}

// ── ProviderVisibilitySection ─────────────────────────

function ProviderVisibilitySection() {
  const [visibility, setVisibility] = useState<Record<string, ProviderVisibilitySetting>>({});
  const [orderSetting, setOrderSetting] = useState<ProviderOrderSetting | undefined>(undefined);
  const [dragId, setDragId] = useState<ProviderId | null>(null);
  const order = effectiveOrder(orderSetting?.order);

  useEffect(() => {
    void loadVisibility().then(setVisibility);
    void loadOrder().then(setOrderSetting);
  }, []);

  // Live storage updates (Mac app may sync visibility while the page is open).
  useEffect(() => {
    const handler = (
      changes: Record<string, browser.Storage.StorageChange>,
      area: string,
    ) => {
      if (area !== 'local') return;
      if ('providerVisibility' in changes) {
        const next = changes['providerVisibility']?.newValue as
          | Record<string, ProviderVisibilitySetting>
          | undefined;
        if (next) setVisibility(next);
      }
      // The Mac app may reorder while this page is open.
      if ('providerOrder' in changes) {
        setOrderSetting(changes['providerOrder']?.newValue as ProviderOrderSetting | undefined);
      }
    };
    browser.storage.onChanged.addListener(handler);
    return () => browser.storage.onChanged.removeListener(handler);
  }, []);

  const handleToggle = (id: ProviderId, enabled: boolean) => {
    // Optimistic update first, then async persist + bridge send.
    const optimistic: Record<string, ProviderVisibilitySetting> = {
      ...visibility,
      [id]: { enabled, lastChangedAt: new Date().toISOString() },
    };
    setVisibility(optimistic);

    void applyVisibilityToggle(id, enabled, visibility, browserSaveVisibility).then(setVisibility);
  };

  const commitOrder = (next: ProviderId[]) => {
    // Optimistic so the row moves immediately; the stamped setting replaces it.
    setOrderSetting({ order: next, lastChangedAt: orderSetting?.lastChangedAt ?? '' });
    void applyOrderChange(next, orderSetting, saveOrder).then(setOrderSetting);
  };

  return (
    <section class="options-section">
      <div class="options-section__header">
        <span class="options-section__icon options-section__icon--providers" aria-hidden="true" />
        <h2 class="options-section__title">Providers</h2>
      </div>
      <p class="options-section__description">
        Choose which providers appear, and drag them (or use the arrows) to set the tab order.
        Both sync automatically when the Mac app is connected; providers only one side has are skipped.
      </p>

      <div class="toggle-group">
        {order.map((id, index) => {
          const meta = PROVIDER_META[id];
          const entry = visibility[id];
          // Default to enabled when no entry exists.
          const isEnabled = entry ? entry.enabled : true;

          return (
            // A div, not a label: a label would forward body clicks to the first button inside it.
            <div
              key={id}
              class={`toggle-row toggle-row--sortable${dragId === id ? ' toggle-row--dragging' : ''}`}
              draggable
              onDragStart={() => setDragId(id)}
              onDragEnd={() => setDragId(null)}
              onDragOver={(e) => e.preventDefault()}
              onDrop={(e) => {
                e.preventDefault();
                if (dragId && dragId !== id) commitOrder(moveToPosition(order, dragId, id));
                setDragId(null);
              }}
            >
              <span class="order-handle" aria-hidden="true" title="Drag to reorder">⠿</span>
              <span class={`toggle-row__icon toggle-row__icon--${id}`} aria-hidden="true" />
              <span class="toggle-row__body">
                <span class="toggle-row__label">{meta.displayName}</span>
                <span class="toggle-row__helper">
                  Hidden in menu bar and popup when off
                </span>
              </span>
              <span class="order-buttons">
                <button
                  type="button"
                  class="order-button"
                  aria-label={`Move ${meta.displayName} up`}
                  disabled={index === 0}
                  onClick={() => commitOrder(moveInOrder(order, id, -1))}
                >
                  ↑
                </button>
                <button
                  type="button"
                  class="order-button"
                  aria-label={`Move ${meta.displayName} down`}
                  disabled={index === order.length - 1}
                  onClick={() => commitOrder(moveInOrder(order, id, 1))}
                >
                  ↓
                </button>
              </span>
              <button
                type="button"
                role="switch"
                aria-checked={isEnabled}
                class={`toggle-switch${isEnabled ? ' toggle-switch--on' : ''}`}
                aria-label={`${isEnabled ? 'Hide' : 'Show'} ${meta.displayName}`}
                onClick={() => handleToggle(id, !isEnabled)}
              >
                <span class="toggle-switch__thumb" />
              </button>
            </div>
          );
        })}
      </div>
    </section>
  );
}

// ── ApiKeySection ─────────────────────────────────────

interface ApiKeySectionProps {
  provider: 'elevenlabs' | 'leonardo';
  title: string;
  hint: string;
}

type KeyStatus = { tone: 'ok' | 'error' | 'busy'; text: string } | null;

/**
 * Optional API key for a provider. The background worker verifies the key with
 * a real call before storing it, so a typo never replaces a working setup.
 * The stored key is never shown again — only "saved" is.
 */
function ApiKeySection({ provider, title, hint }: ApiKeySectionProps) {
  const [hasKey, setHasKey] = useState(false);
  const [draft, setDraft] = useState('');
  const [status, setStatus] = useState<KeyStatus>(null);

  useEffect(() => {
    void getApiKey(provider).then((key) => {
      setHasKey(key !== null);
      if (key !== null) setStatus({ tone: 'ok', text: 'Connected with your API key.' });
    });
  }, [provider]);

  const send = (message: ExtensionMessage): Promise<ExtensionResponse | undefined> =>
    browser.runtime.sendMessage(message) as Promise<ExtensionResponse | undefined>;

  const handleSave = async () => {
    setStatus({ tone: 'busy', text: 'Checking key…' });
    try {
      const res = await send({ kind: 'API_KEY_SAVE', provider, key: draft });
      if (res?.kind === 'API_KEY_RESULT' && res.ok) {
        setHasKey(true);
        setDraft('');
        setStatus({ tone: 'ok', text: 'Connected.' });
      } else if (res?.kind === 'API_KEY_RESULT') {
        setStatus({ tone: 'error', text: res.error });
      } else {
        setStatus({ tone: 'error', text: 'No response from the extension. Try again.' });
      }
    } catch {
      setStatus({ tone: 'error', text: 'Could not reach the extension. Try again.' });
    }
  };

  const handleRemove = async () => {
    await send({ kind: 'API_KEY_REMOVE', provider }).catch(() => undefined);
    setHasKey(false);
    setStatus({ tone: 'ok', text: 'Key removed. Tokenomics will use your signed-in session again.' });
  };

  return (
    <section class="options-section">
      <div class="options-section__header">
        <span class={`options-section__icon options-section__icon--${provider}`} aria-hidden="true" />
        <h2 class="options-section__title">{title}</h2>
      </div>
      <p class="options-section__description">
        API key (optional). {hint} When a key is saved, Tokenomics uses it instead
        of your signed-in session and deletes any session token it saved earlier.
      </p>
      <div class="key-row">
        <input
          class="key-row__input"
          type="password"
          autocomplete="off"
          spellcheck={false}
          aria-label={`${title} API key`}
          placeholder={hasKey ? 'Key saved — paste a new one to replace it' : 'Paste API key'}
          value={draft}
          onInput={(e) => setDraft((e.currentTarget as HTMLInputElement).value)}
        />
        <button
          type="button"
          class="key-row__button"
          disabled={draft.trim().length === 0 || status?.tone === 'busy'}
          onClick={() => void handleSave()}
        >
          Save
        </button>
        {hasKey ? (
          <button type="button" class="options-section__danger" onClick={() => void handleRemove()}>
            Remove
          </button>
        ) : null}
      </div>
      {status ? (
        <p class={`key-row__status key-row__status--${status.tone}`} role="status">
          {status.text}
        </p>
      ) : null}
    </section>
  );
}

// ── LabelModeSection ──────────────────────────────────

/** "Show site names instead of logos" — hidden in logo-free (--text-labels) builds. */
function LabelModeSection() {
  const effective = useTextLabels();
  const [stored, setStored] = useState<boolean | null>(null);

  useEffect(() => {
    void getShowSiteNames().then(setStored);
  }, []);

  if (TEXT_LABELS_ONLY) return null;

  const isOn = stored ?? effective;
  const handleToggle = () => {
    setStored(!isOn);
    void setShowSiteNames(!isOn);
  };

  return (
    <section class="options-section">
      <div class="options-section__header">
        <h2 class="options-section__title">Appearance</h2>
      </div>
      <div class="toggle-group">
        <label class="toggle-row">
          <span class="toggle-row__body">
            <span class="toggle-row__label">Show site names instead of logos</span>
            <span class="toggle-row__helper">
              Popup tabs show plain text names; no logos are displayed
            </span>
          </span>
          <button
            type="button"
            role="switch"
            aria-checked={isOn}
            class={`toggle-switch${isOn ? ' toggle-switch--on' : ''}`}
            aria-label="Show site names instead of logos"
            onClick={handleToggle}
          >
            <span class="toggle-switch__thumb" />
          </button>
        </label>
      </div>
    </section>
  );
}

// ── Component ────────────────────────────────────────

function Options({ onStop }: { onStop: () => void }) {
  useTextLabels(); // applies <html data-labels> so CSS hides logos in text mode
  const [autoPlan, setAutoPlan] = useState<ChatGPTPlan>('unknown');
  // null means no override is set (radio shows 'auto').
  // 'unknown' is never a valid override value so we narrow to PlanChoice.
  const [override, setOverride] = useState<Exclude<PlanChoice, 'auto'> | null>(null);

  // Load initial values from storage.
  useEffect(() => {
    void Promise.all([getChatGPTPlanAuto(), getChatGPTPlanOverride()]).then(
      ([auto, ov]) => {
        setAutoPlan(auto);
        // getChatGPTPlanOverride already filters 'unknown' to null, but the
        // return type is ChatGPTPlan | null. Cast to our narrower type.
        const validOverride =
          ov === 'free' || ov === 'plus' || ov === 'pro' || ov === 'team'
            ? ov
            : null;
        setOverride(validOverride);
      },
    );
  }, []);

  // Keep the auto-detect label fresh if the SW re-detects while the page is open.
  useEffect(() => {
    const handler = (
      changes: Record<string, browser.Storage.StorageChange>,
      area: string,
    ) => {
      if (area !== 'local') return;
      if ('chatgptPlanAuto' in changes) {
        const next = changes['chatgptPlanAuto']?.newValue as ChatGPTPlan | undefined;
        if (next) setAutoPlan(next);
      }
    };
    browser.storage.onChanged.addListener(handler);
    return () => browser.storage.onChanged.removeListener(handler);
  }, []);

  // Derive which radio is currently selected.
  const selected: PlanChoice = override ?? 'auto';

  const handleChange = (choice: PlanChoice) => {
    // Don't optimistically update local state — let storage.onChanged
    // round-trip confirm it. But for snappy feel we can update immediately.
    setOverride(choice === 'auto' ? null : choice);

    const message: ExtensionMessage = {
      kind: 'CHATGPT_SET_PLAN',
      plan: choice,
    };
    void browser.runtime.sendMessage(message).catch((err: unknown) => {
      console.warn('[tokenomics:options] SET_PLAN failed', err);
    });
  };

  const options = buildOptions(autoPlan);

  return (
    <div class="options-page">
      <header class="options-page__header">
        <div class="options-page__wordmark">
          <span class="options-page__wordmark-text">Tokenomics</span>
        </div>
        <h1 class="options-page__title">Settings</h1>
      </header>

      <ProviderVisibilitySection />

      <LabelModeSection />

      <section class="options-section">
        <div class="options-section__header">
          <span class="options-section__icon options-section__icon--chatgpt" aria-hidden="true" />
          <h2 class="options-section__title">ChatGPT</h2>
        </div>
        <p class="options-section__description">
          Override the plan Tokenomics uses to calculate your ChatGPT quotas.
          Auto-detect reads your plan directly from the ChatGPT session — only
          override if detection gets it wrong.
        </p>

        <div class="radio-group" role="radiogroup" aria-label="ChatGPT plan">
          {options.map((opt) => (
            <label
              key={opt.value}
              class="radio-option"
              data-selected={selected === opt.value ? 'true' : 'false'}
            >
              <input
                class="radio-option__input"
                type="radio"
                name="chatgpt-plan"
                value={opt.value}
                checked={selected === opt.value}
                onChange={() => handleChange(opt.value)}
              />
              <span class="radio-option__indicator" aria-hidden="true" />
              <span class="radio-option__body">
                <span class="radio-option__label">{opt.label}</span>
                <span class="radio-option__helper">{opt.helper}</span>
              </span>
            </label>
          ))}
        </div>
      </section>

      <ApiKeySection
        provider="elevenlabs"
        title="ElevenLabs"
        hint="Create one at elevenlabs.io under Developers → API Keys. If you restrict the key, set “User” to “Access”."
      />

      <ApiKeySection
        provider="leonardo"
        title="Leonardo"
        hint="Create one at app.leonardo.ai under API Access (a Leonardo API plan may be required)."
      />

      <section class="options-section">
        <div class="options-section__header">
          <span class="options-section__icon options-section__icon--providers" aria-hidden="true" />
          <h2 class="options-section__title">Tokenomics for Mac</h2>
        </div>
        <p class="options-section__description">
          See all your usage — including Claude Code, Codex, Copilot, and Cursor —
          in your menu bar and desktop widgets.{' '}
          <a
            class="options-section__link"
            href={TRYTOKENOMICS_URL}
            target="_blank"
            rel="noreferrer noopener"
          >
            Get the Mac app →
          </a>
        </p>
      </section>

      <section class="options-section">
        <div class="options-section__header">
          <h2 class="options-section__title">Your data</h2>
        </div>
        <p class="options-section__description">
          Tokenomics only keeps your usage on this computer. Stopping turns off all
          reading and deletes everything it has stored. You’ll be asked again before
          it starts.
        </p>
        <button type="button" class="options-section__danger" onClick={onStop}>
          Stop reading and delete my data
        </button>
      </section>
    </div>
  );
}

/** Shows the consent screen until the user agrees, then the settings page. */
function OptionsRoot() {
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

  const handleStop = async () => {
    await revokeConsentAndClear();
    setConsented(false);
  };

  if (consented === null) return null;
  if (!consented) {
    return (
      <div class="options-page">
        <ConsentScreen onAgree={() => void handleAgree()} />
      </div>
    );
  }
  return <Options onStop={() => void handleStop()} />;
}

// ── Entry ────────────────────────────────────────────

applyTheme();
window
  .matchMedia('(prefers-color-scheme: dark)')
  .addEventListener('change', applyTheme);

const root = document.getElementById('app');
if (root) render(<OptionsRoot />, root);
