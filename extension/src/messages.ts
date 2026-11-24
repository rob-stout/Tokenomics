/**
 * Message protocol between the popup / content scripts and the
 * background service worker.
 */

import type { ProviderUsageSnapshot } from './snapshot';
import type { SunoBilling } from './suno';

export type ExtensionMessage =
  | { kind: 'REFRESH_REQUESTED' }
  /** The user reordered tabs in the popup; the order is already in storage. */
  | { kind: 'ORDER_CHANGED' }
  /** Popup opened: sync with the Mac now instead of waiting for the next heartbeat. */
  | { kind: 'SYNC_NOW' }
  | { kind: 'CONSENT_GRANTED' }
  | { kind: 'CHATGPT_MESSAGE'; model: string | null; ts: number }
  | { kind: 'CHATGPT_SET_PLAN'; plan: 'free' | 'plus' | 'pro' | 'team' | 'auto' }
  | { kind: 'GEMINI_USAGE'; snapshot: ProviderUsageSnapshot }
  /** Firebase ID token grabbed from IndexedDB on elevenlabs.io by the content script. */
  | { kind: 'ELEVENLABS_TOKEN'; token: string }
  /** Cognito ID token + userSub grabbed from localStorage on app.leonardo.ai. */
  | { kind: 'LEONARDO_TOKEN'; idToken: string; userSub: string }
  /** Options page: verify a pasted API key, then store it. */
  | { kind: 'API_KEY_SAVE'; provider: 'elevenlabs' | 'leonardo'; key: string }
  /** Options page: delete the stored API key (capture fallback resumes). */
  | { kind: 'API_KEY_REMOVE'; provider: 'elevenlabs' | 'leonardo' }
  /** Whitelisted billing numbers fetched inside the suno.com page (no token). */
  | { kind: 'SUNO_BILLING'; billing: SunoBilling };

export type ExtensionResponse =
  | { kind: 'REFRESH_COMPLETE' }
  | { kind: 'REFRESH_FAILED'; error: string }
  | { kind: 'REFRESH_BACKOFF'; until: number }
  | { kind: 'API_KEY_RESULT'; ok: true }
  | { kind: 'API_KEY_RESULT'; ok: false; error: string }
  | { kind: 'ACK' };
