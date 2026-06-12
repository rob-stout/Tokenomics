/**
 * ISOLATED-world content script for ElevenLabs Firebase token extraction.
 *
 * Runs on https://elevenlabs.io/* (document_idle). Reads the Firebase ID token
 * and forwards it to the service worker.
 *
 * Firebase Auth persists the signed-in user in ONE of two places depending on
 * the environment: IndexedDB (`firebaseLocalStorageDb` → `firebaseLocalStorage`,
 * the SDK default) OR localStorage (`firebase:authUser:<apiKey>:[DEFAULT]`, used
 * when IndexedDB persistence is unavailable/disabled). Observed live: an account
 * whose token lived only in localStorage while the IndexedDB store was empty, so
 * we MUST check both or the reader silently finds nothing.
 *
 * This script does NOT run in MAIN world — it reads IndexedDB/localStorage
 * directly from the ISOLATED world (both APIs are available there and expose the
 * same data). No inline script injection, no Trusted Types concern.
 *
 * Flow:
 *   1. On document_idle, look for stsTokenManager.accessToken in IndexedDB, then
 *      fall back to the firebase:authUser localStorage entry.
 *   2. Post { kind: 'ELEVENLABS_TOKEN', token } to the SW.
 *   3. Re-poll every 10 min to pick up refreshed tokens (Firebase tokens
 *      expire after ~1 hour and the SDK silently refreshes them).
 */

import browser from 'webextension-polyfill';
import type { ExtensionMessage } from '../messages';

const POLL_INTERVAL_MS = 10 * 60 * 1000;
const DB_NAME = 'firebaseLocalStorageDb';
const STORE_NAME = 'firebaseLocalStorage';

/** Pull `stsTokenManager.accessToken` out of a Firebase user object. */
function accessTokenFrom(value: unknown): string | null {
  const token = (value as Record<string, Record<string, string>> | undefined)
    ?.stsTokenManager?.accessToken;
  return typeof token === 'string' && token.length > 0 ? token : null;
}

/** Primary location: the Firebase SDK's IndexedDB store. */
function readTokenFromIndexedDB(): Promise<string | null> {
  return new Promise((resolve) => {
    const req = indexedDB.open(DB_NAME);

    req.onerror = () => resolve(null);
    req.onsuccess = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.close();
        resolve(null);
        return;
      }

      const tx = db.transaction(STORE_NAME, 'readonly');
      const store = tx.objectStore(STORE_NAME);
      const getAllReq = store.getAll();

      getAllReq.onerror = () => {
        db.close();
        resolve(null);
      };
      getAllReq.onsuccess = () => {
        db.close();
        const entries = getAllReq.result as Array<{ fbase_key?: string; value?: unknown }>;
        for (const entry of entries) {
          const token = accessTokenFrom(entry?.value);
          if (token) {
            resolve(token);
            return;
          }
        }
        resolve(null);
      };
    };
  });
}

/**
 * Fallback location: localStorage `firebase:authUser:<apiKey>:[DEFAULT]`, whose
 * value is the JSON-serialized Firebase user object. Used when the SDK persists
 * to localStorage instead of IndexedDB.
 */
function readTokenFromLocalStorage(): string | null {
  for (const key of Object.keys(localStorage)) {
    if (!key.startsWith('firebase:authUser:')) continue;
    const raw = localStorage.getItem(key);
    if (!raw) continue;
    try {
      const token = accessTokenFrom(JSON.parse(raw));
      if (token) return token;
    } catch {
      // Not JSON / unexpected shape — skip and try the next key.
    }
  }
  return null;
}

async function readFirebaseToken(): Promise<string | null> {
  return (await readTokenFromIndexedDB()) ?? readTokenFromLocalStorage();
}

async function grabAndSend(): Promise<void> {
  try {
    const token = await readFirebaseToken();
    if (!token) return;

    const message: ExtensionMessage = { kind: 'ELEVENLABS_TOKEN', token };
    await browser.runtime.sendMessage(message);
  } catch {
    // SW may be asleep — next poll tick will retry.
  }
}

// Initial grab + periodic refresh to catch token renewals.
void grabAndSend();
const timerId = window.setInterval(() => void grabAndSend(), POLL_INTERVAL_MS);
window.addEventListener('pagehide', () => window.clearInterval(timerId), { once: true });
