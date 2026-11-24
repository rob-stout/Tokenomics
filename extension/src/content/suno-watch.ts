/**
 * ISOLATED-world content script for Suno usage (no MAIN-world script needed).
 *
 * suno.com has no `window.Clerk`, but Clerk stores its ~60 s session JWT in the
 * non-httpOnly `__session` cookie and refreshes it while a suno.com tab is
 * open. This script reads that cookie, uses it as the Bearer for ONE billing
 * request, and sends only the whitelisted numbers (pickBilling) to the service
 * worker. The token is never posted, stored, or logged.
 *
 * Why a content script and not the service worker: the SW has no cookie access
 * without the broad `cookies` permission, and the JWT is only fresh while a
 * suno.com tab keeps refreshing it anyway.
 *
 * CORS: a Chrome content-script fetch carries the PAGE's Origin
 * (https://suno.com), the same origin studio-api already allows for the page's
 * own calls, so no extra host permission is needed. Nothing is fetched until
 * the user has agreed on the consent screen.
 */

import browser from 'webextension-polyfill';
import type { ExtensionMessage } from '../messages';
import { hasConsent } from '../storage';
import { pickBilling, readSessionToken } from '../suno';

const BILLING_URL = 'https://studio-api.prod.suno.com/api/billing/info/';
// Under 5 min so the Mac app's per-provider freshness window stays satisfied.
const POLL_INTERVAL_MS = 4 * 60 * 1000;
const MIN_GAP_MS = 60 * 1000;
// A stale cookie 401s until Clerk mints a new one shortly after page load.
const RETRY_DELAYS_MS = [5_000, 20_000];

const GUARD_KEY = '__tokenomics_suno_active__';
const w = window as unknown as Record<string, unknown>;
if (!w[GUARD_KEY]) {
  w[GUARD_KEY] = true;

  let lastRunAt = 0;
  let inFlight = false;

  /** Returns false when worth retrying soon (no/expired token). */
  async function fetchAndSend(): Promise<boolean> {
    if (inFlight) return true;
    inFlight = true;
    try {
      if (!(await hasConsent())) return true;
      // Signed out (or Clerk hasn't set the cookie yet): stay silent.
      const token = readSessionToken(document.cookie);
      if (!token) return false;

      lastRunAt = Date.now();
      const res = await fetch(BILLING_URL, { headers: { Authorization: `Bearer ${token}` } });
      if (res.status === 401 || res.status === 403) return false;
      if (!res.ok) return true;

      const message: ExtensionMessage = {
        kind: 'SUNO_BILLING',
        billing: pickBilling(await res.json()),
      };
      await browser.runtime.sendMessage(message).catch(() => {
        // SW asleep — the next tick retries.
      });
      return true;
    } catch {
      // Silent observer: never surface errors to the page.
      return true;
    } finally {
      inFlight = false;
    }
  }

  function startWithRetries(attempt: number): void {
    void fetchAndSend().then((ok) => {
      const delay = RETRY_DELAYS_MS[attempt];
      if (!ok && delay !== undefined) window.setTimeout(() => startWithRetries(attempt + 1), delay);
    });
  }

  startWithRetries(0);
  const timerId = window.setInterval(() => void fetchAndSend(), POLL_INTERVAL_MS);

  // Coming back to a long-idle tab: refresh promptly (rate-limited).
  const onVisible = () => {
    if (document.visibilityState === 'visible' && Date.now() - lastRunAt > MIN_GAP_MS) {
      void fetchAndSend();
    }
  };
  document.addEventListener('visibilitychange', onVisible);

  window.addEventListener(
    'pagehide',
    () => {
      window.clearInterval(timerId);
      document.removeEventListener('visibilitychange', onVisible);
    },
    { once: true },
  );
}
