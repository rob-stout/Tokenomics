/**
 * ISOLATED-world content script for Leonardo.ai Cognito token extraction.
 *
 * Runs on https://app.leonardo.ai/* (document_idle). Reads the Cognito ID
 * token and userSub from localStorage and forwards them to the service worker.
 *
 * LocalStorage key pattern (AWS Amplify / Cognito):
 *   CognitoIdentityServiceProvider.<clientId>.<userSub>.idToken
 *   CognitoIdentityServiceProvider.<clientId>.LastAuthUser → contains userSub
 *
 * The clientId is not known ahead of time but is consistent for a given app
 * deployment. We scan all keys matching the Cognito prefix to find them.
 *
 * This script runs in the ISOLATED world — localStorage is shared between
 * MAIN and ISOLATED worlds on the same origin, so no MAIN-world access is
 * needed. No inline script injection, no Trusted Types concern.
 *
 * Flow:
 *   1. On document_idle, scan localStorage for Cognito keys.
 *   2. Find LastAuthUser to get the userSub.
 *   3. Find the matching idToken key.
 *   4. Post { kind: 'LEONARDO_TOKEN', idToken, userSub } to the SW.
 *   5. Re-poll every 10 min to pick up refreshed tokens (Cognito ID tokens
 *      expire after ~1 hour and Amplify silently refreshes them).
 */

import browser from 'webextension-polyfill';
import type { ExtensionMessage } from '../messages';

const POLL_INTERVAL_MS = 10 * 60 * 1000;
const COGNITO_PREFIX = 'CognitoIdentityServiceProvider.';

interface CognitoCredentials {
  idToken: string;
  userSub: string;
}

function readCognitoCredentials(): CognitoCredentials | null {
  // Scan localStorage for the Cognito LastAuthUser key to get the userSub.
  // Key format: CognitoIdentityServiceProvider.<clientId>.LastAuthUser
  let userSub: string | null = null;
  let clientId: string | null = null;

  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (!key?.startsWith(COGNITO_PREFIX)) continue;
    if (key.endsWith('.LastAuthUser')) {
      userSub = localStorage.getItem(key);
      // Extract clientId from the key (segment between prefix and ".LastAuthUser")
      const middle = key.slice(COGNITO_PREFIX.length, key.length - '.LastAuthUser'.length);
      clientId = middle;
      break;
    }
  }

  if (!userSub || !clientId) return null;

  // Now look for the idToken key: CognitoIdentityServiceProvider.<clientId>.<userSub>.idToken
  const idTokenKey = `${COGNITO_PREFIX}${clientId}.${userSub}.idToken`;
  const idToken = localStorage.getItem(idTokenKey);
  if (!idToken || idToken.length === 0) return null;

  return { idToken, userSub };
}

async function grabAndSend(): Promise<void> {
  try {
    const creds = readCognitoCredentials();
    if (!creds) return;

    const message: ExtensionMessage = {
      kind: 'LEONARDO_TOKEN',
      idToken: creds.idToken,
      userSub: creds.userSub,
    };
    await browser.runtime.sendMessage(message);
  } catch {
    // SW may be asleep — next poll tick will retry.
  }
}

// Initial grab + periodic refresh to catch token renewals.
void grabAndSend();
const timerId = window.setInterval(() => void grabAndSend(), POLL_INTERVAL_MS);
window.addEventListener('pagehide', () => window.clearInterval(timerId), { once: true });
