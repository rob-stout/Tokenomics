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
  const meta = PROVIDER_META[provider];

  // Native-only providers (copilot, cursor, gemini) have no web reader — their
  // usage is read locally by the Mac app, so point there, not at a website.
  if (isNativeSource || !isWebProvider(provider)) {
    return (
      <div class="empty-state">
        <p class="empty-state__copy">
          Tokenomics reads {meta.displayName} from the app on your Mac. Open it to see your usage here.
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
          Tokenomics reads your {meta.displayName} usage from the web. Sign in to {signIn.site} to see it here.
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
          Tokenomics counts your ChatGPT usage as you chat. Open {countLocally.site} and send a message.
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
