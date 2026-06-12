/**
 * ISOLATED-world relay for Leonardo.ai Auth0 token capture.
 *
 * leonardo-main.ts runs in MAIN world (declared via `"world": "MAIN"` in the
 * manifest) and intercepts the page's own GraphQL fetch calls to capture the
 * Auth0 access token. It posts results via window.postMessage. This script —
 * running in the default ISOLATED world — listens for those messages and
 * forwards them to the service worker via browser.runtime.sendMessage, which
 * MAIN world cannot call directly.
 *
 * The TAG constant must match the LEO_TAG constant in leonardo-main.ts exactly.
 */

import browser from 'webextension-polyfill';
import type { ExtensionMessage } from '../messages';

// Must match LEO_TAG in leonardo-main.ts exactly.
const LEO_TAG = '__tokenomics_leonardo_msg__';

window.addEventListener('message', (event: MessageEvent) => {
  if (event.source !== window) return;
  const data = event.data as {
    tag?: string;
    kind?: string;
    idToken?: string;
    userSub?: string;
  };
  if (data?.tag !== LEO_TAG) return;
  if (data.kind !== 'LEONARDO_TOKEN') return;
  if (!data.idToken || !data.userSub) return;

  const message: ExtensionMessage = {
    kind: 'LEONARDO_TOKEN',
    idToken: data.idToken,
    userSub: data.userSub,
  };
  browser.runtime.sendMessage(message).catch(() => {
    // SW may be asleep — the next page request will re-trigger the hook.
  });
});
