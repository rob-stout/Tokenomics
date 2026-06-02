/**
 * Message protocol between the popup / content scripts and the
 * background service worker.
 */

import type { ProviderUsageSnapshot } from './snapshot';

export type ExtensionMessage =
  | { kind: 'REFRESH_REQUESTED' }
  | { kind: 'CHATGPT_MESSAGE'; model: string | null; ts: number }
  | { kind: 'CHATGPT_SET_PLAN'; plan: 'free' | 'plus' | 'pro' | 'team' | 'auto' }
  | { kind: 'GEMINI_USAGE'; snapshot: ProviderUsageSnapshot }
  /** Firebase ID token grabbed from IndexedDB on elevenlabs.io by the content script. */
  | { kind: 'ELEVENLABS_TOKEN'; token: string }
  /** Cognito ID token + userSub grabbed from localStorage on app.leonardo.ai. */
  | { kind: 'LEONARDO_TOKEN'; idToken: string; userSub: string };

export type ExtensionResponse =
  | { kind: 'REFRESH_COMPLETE' }
  | { kind: 'REFRESH_FAILED'; error: string }
  | { kind: 'REFRESH_BACKOFF'; until: number }
  | { kind: 'ACK' };
