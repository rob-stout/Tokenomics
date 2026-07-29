import type { BridgeState } from '../../bridge';
import { TRYTOKENOMICS_URL } from '../../urls';

/** Five minutes in milliseconds — beyond this threshold the connection is stale. */
const STALE_THRESHOLD_MS = 5 * 60 * 1000;

interface Props {
  bridgeState: BridgeState | null;
}

/**
 * Slim banner at the top of the popup that signals Mac app connection status.
 *
 * - No bridge data yet or stale (>5min): "Mac app not detected" warning with
 *   install link. Shown only once storage has been loaded (bridgeState !== null).
 * - Recent success: "Connected to Tokenomics x.y.z" in a subtle footer chip.
 * - Recent success but with error entries: small warning indicator instead.
 */
export function BridgeBanner({ bridgeState }: Props) {
  if (!bridgeState) return null;

  const { lastSuccessAt, lastMacAppVersion, status } = bridgeState;
  const now = Date.now();
  const isConnected = lastSuccessAt !== null && now - lastSuccessAt < STALE_THRESHOLD_MS;

  if (!isConnected) {
    return (
      <div class="bridge-banner bridge-banner--warn" role="status" aria-live="polite">
        <span class="bridge-banner__text">
          Mac app not detected.{' '}
          <a
            class="bridge-banner__link"
            href={TRYTOKENOMICS_URL}
            target="_blank"
            rel="noreferrer noopener"
          >
            Install Tokenomics
          </a>{' '}
          to see menu-bar usage.
        </span>
      </div>
    );
  }

  // Check if there are recent errors even though we have a connection.
  const recentErrors = status.slice(-5).some((e) => e.level === 'error');

  if (recentErrors) {
    return (
      <div class="bridge-banner bridge-banner--caution" role="status">
        <span class="bridge-banner__text">Mac app connection unstable</span>
      </div>
    );
  }

  // Happy path — subtle connected chip (uses footer slot visually).
  return (
    <div class="bridge-banner bridge-banner--ok" role="status" aria-label={`Connected to Tokenomics ${lastMacAppVersion ?? ''}`}>
      <span class="bridge-banner__connected-dot" aria-hidden="true" />
      <span class="bridge-banner__text">
        Tokenomics {lastMacAppVersion ?? 'connected'}
      </span>
    </div>
  );
}
