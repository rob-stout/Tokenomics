import { PROVIDER_META, type ProviderId } from '../../types';
import { isWebProvider, SIGN_IN, COUNT_LOCALLY } from '../popup-logic';

interface Props {
  provider: ProviderId;
  /** When true, this provider's data comes from the Mac app — show the Mac install CTA. */
  isNativeSource?: boolean;
}

const COMING_SOON: ReadonlySet<ProviderId> = new Set([]);
const TRYTOKENOMICS_URL = 'https://trytokenomics.com';

export function EmptyState({ provider, isNativeSource = false }: Props) {
  // Native-only providers (copilot, cursor, gemini) have no web reader.
  // Their empty state should ask the user to open the Mac app, not a website.
  if (isNativeSource || !isWebProvider(provider)) {
    const meta = PROVIDER_META[provider];
    return (
      <div class="empty-state">
        <p class="empty-state__copy">
          Connect the Tokenomics menu bar app to see {meta.displayName} usage here.
        </p>
        <a
          class="empty-state__cta"
          href={TRYTOKENOMICS_URL}
          target="_blank"
          rel="noreferrer noopener"
        >
          Open Tokenomics →
        </a>
      </div>
    );
  }

  const signIn = SIGN_IN[provider];
  if (signIn) {
    return (
      <div class="empty-state">
        <p class="empty-state__copy">
          Sign in to {signIn.site} in your browser to start tracking your usage.
        </p>
        <a
          class="empty-state__cta"
          href={signIn.url}
          target="_blank"
          rel="noreferrer noopener"
        >
          Open {signIn.site} →
        </a>
      </div>
    );
  }

  const countLocally = COUNT_LOCALLY[provider];
  if (countLocally) {
    return (
      <div class="empty-state">
        <p class="empty-state__copy">
          Open {countLocally.site} and send a message — your usage is
          counted locally as you chat.
        </p>
        <a
          class="empty-state__cta"
          href={countLocally.url}
          target="_blank"
          rel="noreferrer noopener"
        >
          Open {countLocally.site} →
        </a>
      </div>
    );
  }

  if (COMING_SOON.has(provider)) {
    return (
      <div class="empty-state">
        <p class="empty-state__copy">Coming in the next update.</p>
      </div>
    );
  }

  const meta = PROVIDER_META[provider];
  return (
    <div class="empty-state">
      <p class="empty-state__copy">
        Track {meta.displayName} in the Tokenomics menu bar app.
      </p>
      <a
        class="empty-state__cta"
        href={TRYTOKENOMICS_URL}
        target="_blank"
        rel="noreferrer noopener"
      >
        Install Tokenomics →
      </a>
    </div>
  );
}
