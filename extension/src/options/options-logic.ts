/**
 * Pure business logic for the options page — no DOM, no browser APIs.
 * Extracted so unit tests can import without pulling in webextension-polyfill.
 */

import type { ProviderOrderSetting, ProviderVisibilitySetting } from '../bridge-types';
import { stampUserOrder } from '../provider-order';
import { scheduleBridgeSend, type BridgeSendReason } from '../bridge';
import type { ProviderId } from '../types';

/** Raw chrome.storage.local.set wrapper — injected so tests can mock it. */
export type StorageSetter = (
  map: Record<string, ProviderVisibilitySetting>,
) => Promise<void>;

/** Bridge send trigger — injected so tests can count invocations without needing to spy on bundled exports. */
export type BridgeSender = (reason: BridgeSendReason) => void;

/**
 * Toggle a single provider's enabled state. Writes the updated map using
 * the provided storage setter and schedules a bridge send so the Mac app
 * stays in sync.
 *
 * `sendBridge` defaults to `scheduleBridgeSend` from bridge.ts so callers
 * in production don't need to pass it. Tests inject a spy instead.
 *
 * Returns the updated visibility map.
 */
export async function applyVisibilityToggle(
  providerId: ProviderId,
  enabled: boolean,
  existingMap: Record<string, ProviderVisibilitySetting>,
  setStorage: StorageSetter,
  sendBridge: BridgeSender = scheduleBridgeSend,
): Promise<Record<string, ProviderVisibilitySetting>> {
  const updated: Record<string, ProviderVisibilitySetting> = {
    ...existingMap,
    [providerId]: {
      enabled,
      lastChangedAt: new Date().toISOString(),
    },
  };
  await setStorage(updated);
  sendBridge('settings');
  return updated;
}

/**
 * Save a user reorder: stamp it (so it beats an older Mac order), store it, and
 * schedule a bridge send. Returns the stored setting.
 */
export async function applyOrderChange(
  order: readonly ProviderId[],
  previous: ProviderOrderSetting | undefined,
  setStorage: (setting: ProviderOrderSetting) => Promise<void>,
  sendBridge: BridgeSender = scheduleBridgeSend,
): Promise<ProviderOrderSetting> {
  const setting = stampUserOrder(order, previous);
  await setStorage(setting);
  sendBridge('settings');
  return setting;
}
