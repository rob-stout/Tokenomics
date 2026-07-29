import { render } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import browser from 'webextension-polyfill';
import type { ExtensionMessage } from '../messages';
import type { ChatGPTPlan } from '../chatgpt';
import type { ProviderVisibilitySetting } from '../bridge-types';
import { getChatGPTPlanAuto, getChatGPTPlanOverride } from '../storage';
import { PROVIDERS, PROVIDER_META, type ProviderId } from '../types';
import { TRYTOKENOMICS_URL } from '../urls';
import { applyVisibilityToggle } from './options-logic';

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

  useEffect(() => {
    void loadVisibility().then(setVisibility);
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

  return (
    <section class="options-section">
      <div class="options-section__header">
        <span class="options-section__icon options-section__icon--providers" aria-hidden="true" />
        <h2 class="options-section__title">Provider Visibility</h2>
      </div>
      <p class="options-section__description">
        Choose which providers appear in the popup and in the Tokenomics menu bar app.
        Changes sync automatically when the Mac app is connected.
      </p>

      <div class="toggle-group">
        {PROVIDERS.map((id) => {
          const meta = PROVIDER_META[id];
          const entry = visibility[id];
          // Default to enabled when no entry exists.
          const isEnabled = entry ? entry.enabled : true;

          return (
            <label key={id} class="toggle-row">
              <span class={`toggle-row__icon toggle-row__icon--${id}`} aria-hidden="true" />
              <span class="toggle-row__body">
                <span class="toggle-row__label">{meta.displayName}</span>
                <span class="toggle-row__helper">
                  Hidden in menu bar and popup when off
                </span>
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
            </label>
          );
        })}
      </div>
    </section>
  );
}

// ── Component ────────────────────────────────────────

function Options() {
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
    </div>
  );
}

// ── Entry ────────────────────────────────────────────

applyTheme();
window
  .matchMedia('(prefers-color-scheme: dark)')
  .addEventListener('change', applyTheme);

const root = document.getElementById('app');
if (root) render(<Options />, root);
