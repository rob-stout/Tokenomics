/**
 * ISOLATED-world content script for ElevenLabs Firebase token extraction.
 *
 * Runs on https://elevenlabs.io/* (document_idle). Reads the Firebase ID token
 * from IndexedDB (`firebaseLocalStorageDb` → `firebaseLocalStorage` object
 * store) and forwards it to the service worker.
 *
 * This script does NOT run in MAIN world — it reads IndexedDB directly from
 * the ISOLATED world (the IndexedDB API is available in both worlds and exposes
 * the same databases). No inline script injection, no Trusted Types concern.
 *
 * Flow:
 *   1. On document_idle, open the IndexedDB and scan firebaseLocalStorage.
 *   2. Find the entry whose value contains stsTokenManager.accessToken.
 *   3. Post { kind: 'ELEVENLABS_TOKEN', token } to the SW.
 *   4. Re-poll every 10 min to pick up refreshed tokens (Firebase tokens
 *      expire after ~1 hour and the SDK silently refreshes them).
 */

import browser from 'webextension-polyfill';
import type { ExtensionMessage } from '../messages';

const POLL_INTERVAL_MS = 10 * 60 * 1000;
const DB_NAME = 'firebaseLocalStorageDb';
const STORE_NAME = 'firebaseLocalStorage';

async function readFirebaseToken(): Promise<string | null> {
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
          // Each entry's `value` is a Firebase user object with stsTokenManager.
          const accessToken = (
            entry?.value as Record<string, Record<string, string>> | undefined
          )?.stsTokenManager?.accessToken;
          if (typeof accessToken === 'string' && accessToken.length > 0) {
            resolve(accessToken);
            return;
          }
        }
        resolve(null);
      };
    };
  });
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
