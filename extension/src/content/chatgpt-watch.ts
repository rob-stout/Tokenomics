/**
 * Content script bridge for ChatGPT counter.
 *
 * Runs at document_start in the ISOLATED world (default for content
 * scripts). Injects a MAIN-world <script> that monkey-patches fetch +
 * XMLHttpRequest so we can observe POSTs to /backend-api/conversation
 * BEFORE they're consumed by the React app. MV3 webRequest can't read
 * request bodies; this is the standard workaround.
 *
 * The MAIN-world script can't call chrome.* APIs, so it posts an event
 * back to us via window.postMessage with a private tag, which we relay
 * to the service worker via chrome.runtime.sendMessage.
 */

import browser from 'webextension-polyfill';
import type { ExtensionMessage } from '../messages';
import { hasConsent } from '../storage';

const TAG = '__tokenomics_chatgpt_msg__';

// Inject the MAIN-world patch. Using a <script> tag with src is the
// canonical way to escape the content-script sandbox in MV3.
function injectMainWorldPatch(): void {
  const code = `(${mainWorldPatch.toString()})(${JSON.stringify(TAG)});`;
  const el = document.createElement('script');
  el.textContent = code;
  (document.head || document.documentElement).appendChild(el);
  el.remove();
}

// This function is serialized to a string and re-executed in MAIN world.
// It must not close over any content-script variables.
function mainWorldPatch(tag: string): void {
  // Avoid double-injection if the script reloads.
  if ((window as unknown as Record<string, unknown>)[tag]) return;
  (window as unknown as Record<string, unknown>)[tag] = true;

  const originalFetch = window.fetch.bind(window);

  window.fetch = async function patchedFetch(input: RequestInfo | URL, init?: RequestInit) {
    try {
      const url =
        typeof input === 'string'
          ? input
          : input instanceof URL
            ? input.href
            : input.url;

      const isPost = init?.method?.toUpperCase() === 'POST' || (input instanceof Request && input.method === 'POST');

      if (
        isPost &&
        typeof url === 'string' &&
        url.includes('/backend-api/conversation')
      ) {
        let model: string | null = null;
        try {
          // The conversation POST body is JSON: { model: 'gpt-5', ... }
          const body = init?.body;
          if (typeof body === 'string') {
            const parsed = JSON.parse(body) as { model?: string };
            if (typeof parsed.model === 'string') model = parsed.model;
          }
        } catch {
          // Body wasn't JSON or model wasn't there; record null and move on.
        }
        window.postMessage({ tag, kind: 'CHATGPT_MESSAGE', model, ts: Date.now() }, '*');
      }
    } catch {
      // Never let patch errors break the page's own fetch.
    }
    return originalFetch(input, init);
  };
}

window.addEventListener('message', async (event: MessageEvent) => {
  if (event.source !== window) return;
  const data = event.data as { tag?: string; kind?: string; model?: string | null; ts?: number };
  if (data?.tag !== TAG) return;
  if (data.kind !== 'CHATGPT_MESSAGE') return;

  // Nothing leaves the page until the user agrees on the consent screen.
  if (!(await hasConsent())) return;

  const message: ExtensionMessage = {
    kind: 'CHATGPT_MESSAGE',
    model: data.model ?? null,
    ts: typeof data.ts === 'number' ? data.ts : Date.now(),
  };
  browser.runtime.sendMessage(message).catch(() => {
    // SW may be asleep; the message will be re-fired on the next user
    // action. We don't retry — the counter would over-report.
  });
});

injectMainWorldPatch();
