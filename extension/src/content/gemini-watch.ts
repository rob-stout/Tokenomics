/**
 * ISOLATED-world relay for Gemini consumer usage.
 *
 * gemini-main.ts runs in MAIN world (declared via `"world": "MAIN"` in the
 * manifest) and posts results as window.postMessage. This script — running in
 * the default ISOLATED world — listens for those messages and forwards them to
 * the service worker via browser.runtime.sendMessage, which MAIN world cannot
 * call directly.
 *
 * The previous approach (el.textContent = code inline-script injection) threw
 * a Trusted Types violation on gemini.google.com:
 *   "This document requires 'TrustedScript' assignment."
 * Using `"world": "MAIN"` in the manifest is the correct MV3 replacement.
 */

import browser from 'webextension-polyfill';
import type { ExtensionMessage } from '../messages';
import type { ProviderUsageSnapshot } from '../snapshot';

// Must match the TAG constant in gemini-main.ts exactly.
const TAG = '__tokenomics_gemini_msg__';

window.addEventListener('message', (event: MessageEvent) => {
  if (event.source !== window) return;
  const data = event.data as {
    tag?: string;
    kind?: string;
    snapshot?: ProviderUsageSnapshot;
  };
  if (data?.tag !== TAG) return;
  if (data.kind !== 'GEMINI_USAGE') return;
  if (!data.snapshot) return;

  const message: ExtensionMessage = {
    kind: 'GEMINI_USAGE',
    snapshot: data.snapshot,
  };
  browser.runtime.sendMessage(message).catch(() => {
    // SW may be asleep — the next 5-min timer tick in gemini-main.ts will retry.
  });
});
