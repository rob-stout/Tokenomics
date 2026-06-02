/**
 * MAIN-world content script for Gemini consumer usage.
 *
 * Declared in manifest.json with `"world": "MAIN"` so it runs directly in the
 * page's JavaScript context — no inline <script> injection, no Trusted Types
 * violation. gemini.google.com enforces `require-trusted-types-for 'script'`,
 * which blocks the previous `el.textContent = code` approach.
 *
 * This script MUST NOT use any chrome.* / browser.* APIs — those are only
 * available in the ISOLATED world. Results are posted back to gemini-watch.ts
 * (the ISOLATED relay) via window.postMessage.
 *
 * Flow:
 *   1. On document_start, poll briefly for WIZ_global_data (the page sets
 *      session tokens after DOMContentLoaded — typically within a few seconds).
 *   2. Once tokens appear, replay the jSf9Qc batchexecute RPC from the page's
 *      own session credentials (XSRF + f.sid + bl). These tokens expire with the
 *      session and are not available in the service worker.
 *   3. Parse the response via extractRpc + mapToSnapshot (duplicated from
 *      gemini.ts — this script is a standalone IIFE; it cannot import modules).
 *   4. Post { tag, kind: 'GEMINI_USAGE', snapshot } via window.postMessage('*').
 *   5. Re-poll every 5 min while the tab is alive; clear on pagehide.
 */

// --- constants shared with gemini-watch.ts (must match exactly) ---
const TAG = '__tokenomics_gemini_msg__';
const POLL_INTERVAL_MS = 5 * 60 * 1000;

// --- idempotency guard (soft-nav protection) ---
const GUARD_KEY = '__tokenomics_gemini_active__';
const w = window as unknown as Record<string, unknown>;
if (!w[GUARD_KEY]) {
  w[GUARD_KEY] = true;

  // ── batchexecute helpers ────────────────────────────────────────────────────
  // Duplicated from src/gemini.ts — DO NOT import from there; this is a
  // MAIN-world IIFE with no module system available at runtime.

  /** Strip the batchexecute envelope; return the decoded inner payload for rpcid. */
  function extractRpc(text: string, rpcid: string): unknown | null {
    for (const line of text.split('\n')) {
      if (!line.startsWith('[["wrb.fr"')) continue;
      let outer: unknown;
      try {
        outer = JSON.parse(line);
      } catch {
        continue;
      }
      if (!Array.isArray(outer)) continue;
      for (const entry of outer as unknown[]) {
        if (
          Array.isArray(entry) &&
          (entry as unknown[])[0] === 'wrb.fr' &&
          (entry as unknown[])[1] === rpcid &&
          typeof (entry as unknown[])[2] === 'string'
        ) {
          try {
            return JSON.parse((entry as unknown[])[2] as string);
          } catch {
            return null;
          }
        }
      }
    }
    return null;
  }

  /** Safely coerce an unknown value to a finite number; returns 0 otherwise. */
  function num(v: unknown): number {
    return typeof v === 'number' && Number.isFinite(v) ? v : 0;
  }

  const FIVE_HOUR_SEC = 5 * 3600;
  const WEEK_SEC = 7 * 86400;
  const PERIOD_LABEL: Record<number, string> = { 1: '5-Hour Window', 2: 'Weekly' };

  /**
   * Map the decoded jSf9Qc payload to a ProviderUsageSnapshot shape.
   *
   * index0 = remaining compute units (unused here — counts down with use).
   * index1 = utilization fraction 0–1 (used / cap) → utilization% = index1 * 100.
   * Confirmed via a before/after capture 2026-06-02: a task that burned 227 units
   * took index0 600→373 and index1 0→0.38 = 227/600.
   */
  function mapToSnapshot(inner: unknown, now: number): unknown {
    const windows: unknown[] =
      Array.isArray((inner as unknown[] | null)?.[1])
        ? (inner as unknown[])[1] as unknown[]
        : [];

    let shortWindow: unknown | null = null;
    let longWindow: unknown | null = null;

    for (const win of windows) {
      const utilFraction = num((win as unknown[])?.[1]);
      const periodType = num((win as unknown[])?.[2]);
      const resetSec = num(((win as unknown[])?.[3] as unknown[][])?.[0]?.[0]);

      const entry = {
        label: PERIOD_LABEL[periodType] ?? `Window ${periodType}`,
        utilization: Math.min(100, Math.max(0, Math.round(utilFraction * 100))),
        resetsAt: resetSec > 0 ? new Date(resetSec * 1000).toISOString() : '',
        windowDurationSec: periodType === 2 ? WEEK_SEC : FIVE_HOUR_SEC,
      };

      if (periodType === 2) {
        longWindow = entry;
      } else {
        shortWindow = entry;
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

  // ── RPC replay ──────────────────────────────────────────────────────────────

  async function fetchAndPost(): Promise<void> {
    try {
      const wiz = (window as unknown as Record<string, unknown>).WIZ_global_data as
        | Record<string, string>
        | undefined ?? {};

      // If session tokens are absent the user is likely logged out — skip
      // silently rather than firing a 400 at the batchexecute endpoint.
      if (!wiz.SNlM0e && !wiz.FdrFJe) return;

      const params = new URLSearchParams({
        rpcids: 'jSf9Qc',
        'source-path': '/usage',
        bl: wiz.cfb2h ?? '',
        'f.sid': wiz.FdrFJe ?? '',
        hl: 'en',
        _reqid: String(Math.floor(Math.random() * 1e6)),
        rt: 'c',
      });

      const body = new URLSearchParams();
      body.set('f.req', JSON.stringify([[['jSf9Qc', '[]', null, 'generic']]]));
      if (wiz.SNlM0e) body.set('at', wiz.SNlM0e);

      const res = await fetch(
        '/_/BardChatUi/data/batchexecute?' + params.toString(),
        {
          method: 'POST',
          credentials: 'include',
          headers: { 'content-type': 'application/x-www-form-urlencoded;charset=UTF-8' },
          body: body.toString(),
        },
      );

      if (!res.ok) return;
      const text = await res.text();
      const inner = extractRpc(text, 'jSf9Qc');
      if (!inner) return;

      const snapshot = mapToSnapshot(inner, Date.now());
      window.postMessage({ tag: TAG, kind: 'GEMINI_USAGE', snapshot }, '*');
    } catch {
      // Never surface fetch errors to the page — we are a silent observer.
    }
  }

  // ── startup poll ────────────────────────────────────────────────────────────
  // WIZ_global_data isn't populated at document_start; the page's bootstrap
  // sets it shortly after. Poll up to ~20s before giving up on the first call.

  function startWhenReady(attempt: number): void {
    const wiz = (window as unknown as Record<string, unknown>).WIZ_global_data as
      | Record<string, string>
      | undefined;
    if (wiz?.SNlM0e) {
      void fetchAndPost();
      return;
    }
    if (attempt < 40) window.setTimeout(() => startWhenReady(attempt + 1), 500);
  }

  startWhenReady(0);
  const timerId = window.setInterval(() => void fetchAndPost(), POLL_INTERVAL_MS);

  // Clean up on SPA navigations so we don't accumulate ghost timers.
  window.addEventListener('pagehide', () => window.clearInterval(timerId), { once: true });
}
