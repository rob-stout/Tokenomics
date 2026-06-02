/**
 * Content script bridge for Gemini consumer usage.
 *
 * Mirrors the MAIN-world ↔ ISOLATED ↔ service-worker relay pattern from
 * chatgpt-watch.ts, but instead of monkey-patching fetch, the MAIN-world
 * script replays the jSf9Qc batchexecute RPC using the page's own session
 * tokens (WIZ_global_data.SNlM0e / FdrFJe / cfb2h). These tokens expire and
 * are not accessible from the service worker, so the replay must happen here
 * in MAIN world where the page's JavaScript context is live.
 *
 * Flow:
 *   1. On load: MAIN-world script reads WIZ_global_data, replays the RPC,
 *      parses the jSf9Qc inner payload via extractRpc/mapToSnapshot, and
 *      posts { tag, kind: 'GEMINI_USAGE', snapshot } via window.postMessage.
 *   2. ISOLATED script (this file) receives the message and relays it to the
 *      service worker via chrome.runtime.sendMessage (MAIN world can't call
 *      chrome.* APIs in MV3).
 *   3. Service worker stores the snapshot and bridges it to the Mac app.
 *
 * Re-polling: the MAIN-world script runs once on load, then re-polls on a
 * timer (~5 min) so long as the tab remains open. On page unload the timer
 * is cleared automatically.
 */

import browser from 'webextension-polyfill';
import type { ExtensionMessage } from '../messages';
import type { ProviderUsageSnapshot } from '../snapshot';

const TAG = '__tokenomics_gemini_msg__';
const POLL_INTERVAL_MS = 5 * 60 * 1000; // re-poll every 5 min while tab is alive

// Inject the MAIN-world script. Using a <script> tag with inline code is the
// standard MV3 technique for escaping the content-script sandbox.
function injectMainWorldPatch(): void {
  const code = `(${mainWorldPatch.toString()})(${JSON.stringify(TAG)}, ${POLL_INTERVAL_MS});`;
  const el = document.createElement('script');
  el.textContent = code;
  (document.head || document.documentElement).appendChild(el);
  el.remove();
}

// This function is serialized to a string and re-executed in MAIN world.
// It must not close over any content-script variables (different JS context).
function mainWorldPatch(tag: string, pollIntervalMs: number): void {
  // Idempotency guard — avoid double-injection on soft navigations.
  const guard = '__tokenomics_gemini_active__';
  if ((window as unknown as Record<string, unknown>)[guard]) return;
  (window as unknown as Record<string, unknown>)[guard] = true;

  // ── batchexecute helpers ──────────────────────────────────────────

  /** Strip the batchexecute envelope; return the decoded inner payload for rpcid. */
  function extractRpc(text: string, rpcid: string): unknown | null {
    for (const line of text.split('\n')) {
      if (!line.startsWith('[["wrb.fr"')) continue;
      let outer: unknown;
      try { outer = JSON.parse(line); } catch { continue; }
      if (!Array.isArray(outer)) continue;
      for (const entry of outer as unknown[]) {
        if (
          Array.isArray(entry) &&
          (entry as unknown[])[0] === 'wrb.fr' &&
          (entry as unknown[])[1] === rpcid &&
          typeof (entry as unknown[])[2] === 'string'
        ) {
          try { return JSON.parse((entry as unknown[])[2] as string); } catch { return null; }
        }
      }
    }
    return null;
  }

  function num(v: unknown): number {
    return typeof v === 'number' && Number.isFinite(v) ? v : 0;
  }

  /** Map the decoded jSf9Qc payload to a ProviderUsageSnapshot shape. */
  function mapToSnapshot(inner: unknown, now: number): unknown {
    const FIVE_HOUR_SEC = 5 * 3600;
    const WEEK_SEC = 7 * 86400;
    const PERIOD_LABEL: Record<number, string> = { 1: '5-Hour Window', 2: 'Weekly' };

    const windows: unknown[] =
      Array.isArray((inner as unknown[] | null)?.[1]) ? (inner as unknown[])[1] as unknown[] : [];

    let shortWindow: unknown | null = null;
    let longWindow: unknown | null = null;

    for (const w of windows) {
      // index0 = remaining units (unused); index1 = utilization fraction (0–1).
      // Mirrors gemini.ts mapToSnapshot — keep the two in sync (see note below).
      const utilFraction = num((w as unknown[])?.[1]);
      const periodType = num((w as unknown[])?.[2]);
      const resetSec = num(((w as unknown[])?.[3] as unknown[][])?.[0]?.[0]);

      const win = {
        label: PERIOD_LABEL[periodType] ?? `Window ${periodType}`,
        utilization: Math.min(100, Math.max(0, Math.round(utilFraction * 100))),
        resetsAt: resetSec > 0 ? new Date(resetSec * 1000).toISOString() : '',
        windowDurationSec: periodType === 2 ? WEEK_SEC : FIVE_HOUR_SEC,
      };

      if (periodType === 2) {
        longWindow = win;
      } else {
        shortWindow = win;
      }
    }

    return {
      provider: 'geminiConsumer',
      shortWindow: shortWindow ?? {
        label: '5-Hour Window',
        utilization: 0,
        resetsAt: '',
        windowDurationSec: FIVE_HOUR_SEC,
      },
      longWindow,
      extras: {},
      planLabel: 'Gemini',
      capturedAt: now,
      estimated: false,
    };
  }

  // ── RPC replay ────────────────────────────────────────────────────

  async function fetchAndPost(): Promise<void> {
    try {
      const w = (window as unknown as Record<string, unknown>).WIZ_global_data as Record<string, string> | undefined ?? {};
      // Page tokens expire with the session — if they're absent the tab is
      // probably logged out, so skip silently rather than sending a 400.
      if (!w.SNlM0e && !w.FdrFJe) return;

      const params = new URLSearchParams({
        rpcids: 'jSf9Qc',
        'source-path': '/usage',
        bl: w.cfb2h ?? '',
        'f.sid': w.FdrFJe ?? '',
        hl: 'en',
        _reqid: String(Math.floor(Math.random() * 1e6)),
        rt: 'c',
      });

      const body = new URLSearchParams();
      body.set('f.req', JSON.stringify([[['jSf9Qc', '[]', null, 'generic']]]));
      if (w.SNlM0e) body.set('at', w.SNlM0e);

      const res = await fetch(
        '/_/BardChatUi/data/batchexecute?' + params.toString(),
        {
          method: 'POST',
          credentials: 'include',
          headers: { 'content-type': 'application/x-www-form-urlencoded;charset=UTF-8' },
          body: body.toString(),
        },
      );

      if (!res.ok) return; // non-200: tab might be loading or user is signed out
      const text = await res.text();
      const inner = extractRpc(text, 'jSf9Qc');
      if (!inner) return;

      const snapshot = mapToSnapshot(inner, Date.now());
      window.postMessage({ tag, kind: 'GEMINI_USAGE', snapshot }, '*');
    } catch {
      // Never let a fetch error surface to the page — we're a silent observer.
    }
  }

  // WIZ_global_data isn't populated at document_start — the page's bootstrap
  // sets the session tokens slightly later. Poll briefly for readiness before
  // the first real fetch, otherwise the initial call bails token-less and the
  // first successful read wouldn't land until a full pollIntervalMs later.
  function startWhenReady(attempt: number): void {
    const w = (window as unknown as Record<string, unknown>).WIZ_global_data as Record<string, string> | undefined;
    if (w && w.SNlM0e) { void fetchAndPost(); return; }
    if (attempt < 40) window.setTimeout(() => startWhenReady(attempt + 1), 500); // wait up to ~20s
  }
  startWhenReady(0);
  const timerId = window.setInterval(() => void fetchAndPost(), pollIntervalMs);

  // Clean up when the page unloads to avoid ghost timers on SPA navigations.
  window.addEventListener('pagehide', () => window.clearInterval(timerId), { once: true });
}

// ── ISOLATED world: relay to service worker ───────────────────────

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
    // SW may be asleep — the next timer tick will retry. We don't retry
    // immediately to avoid double-counting or stale data races.
  });
});

injectMainWorldPatch();
