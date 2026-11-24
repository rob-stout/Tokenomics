/**
 * Preact hook shared by the popup and options page: reads the "show site names
 * instead of logos" setting, keeps it live, and mirrors it onto
 * <html data-labels="text|logo"> so CSS can hide every vendor logo at once.
 */

import { useEffect, useState } from 'preact/hooks';
import browser from 'webextension-polyfill';
import { resolveTextLabels } from './labels';
import { getShowSiteNames } from './storage';

export function useTextLabels(): boolean {
  const [textLabels, setTextLabels] = useState<boolean>(() => resolveTextLabels(null));

  useEffect(() => {
    void getShowSiteNames().then((stored) => setTextLabels(resolveTextLabels(stored)));

    const handler = (changes: Record<string, browser.Storage.StorageChange>, area: string) => {
      if (area !== 'local' || !('showSiteNames' in changes)) return;
      const next = changes['showSiteNames']?.newValue;
      setTextLabels(resolveTextLabels(typeof next === 'boolean' ? next : null));
    };
    browser.storage.onChanged.addListener(handler);
    return () => browser.storage.onChanged.removeListener(handler);
  }, []);

  useEffect(() => {
    document.documentElement.dataset.labels = textLabels ? 'text' : 'logo';
  }, [textLabels]);

  return textLabels;
}
