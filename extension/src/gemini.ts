/**
 * Gemini consumer usage reader — parses the jSf9Qc batchexecute RPC.
 *
 * The usage data lives on gemini.google.com/usage and is fetched from a
 * batchexecute endpoint that requires page-context tokens (XSRF, f.sid, bl).
 * Those tokens expire and aren't available in the service worker, so this
 * module is called from a MAIN-world content script that replays the RPC
 * with the page's own credentials, then relays the parsed snapshot to the SW.
 *
 * Payload shape (jSf9Qc inner payload, schema version 1):
 *   [schemaVer, [ [remaining, utilFraction, periodType, [[resetEpochSec, resetNanos]]], … ], boolFlag]
 *
 * periodType 1 = 5-Hour rolling window, periodType 2 = Weekly window.
 *   - index0 = remaining compute units (counts DOWN as you use Gemini)
 *   - index1 = utilization as a 0–1 fraction (i.e. used / cap)
 * So utilization% = index1 * 100. (Confirmed 2026-06-02 via a before/after
 * capture: a task that burned 227 units took 5h index0 600→373 and index1
 * 0→0.38 = 227/600; weekly index0 12096→11869, index1 0→0.0187 = 227/12096.
 * At 0% the two fields are indistinguishable, which is why the initial
 * `[cap, used]` reading looked plausible — it wasn't.)
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

const FIVE_HOUR_SEC = 5 * 3600;
const WEEK_SEC = 7 * 86400;

// Human-readable labels for the popover / widget surfaces.
const PERIOD_LABEL: Record<number, string> = {
  1: '5-Hour Window',
  2: 'Weekly',
};

/**
 * Strip the batchexecute envelope and return the decoded inner payload for
 * the given rpcid. Returns null on any parse failure so callers can fail
 * gracefully rather than crash.
 *
 * The envelope looks like:
 *   )]}'
 *   <length>\n
 *   [["wrb.fr","jSf9Qc","<JSON-escaped inner payload>",null,null,null,"generic"],…]
 */
export function extractRpc(responseText: string, rpcid: string): unknown | null {
  for (const line of responseText.split('\n')) {
    if (!line.startsWith('[["wrb.fr"')) continue;
    let outer: unknown;
    try {
      outer = JSON.parse(line);
    } catch {
      continue;
    }
    if (!Array.isArray(outer)) continue;
    for (const entry of outer) {
      if (
        Array.isArray(entry) &&
        entry[0] === 'wrb.fr' &&
        entry[1] === rpcid &&
        typeof entry[2] === 'string'
      ) {
        try {
          return JSON.parse(entry[2]);
        } catch {
          return null;
        }
      }
    }
  }
  return null;
}

/**
 * Map the decoded jSf9Qc inner payload to a ProviderUsageSnapshot.
 *
 * Pure function — exported for unit testing. Takes the raw decoded array
 * (result of JSON.parse on entry[2]) and a "now" timestamp in milliseconds.
 */
export function mapToSnapshot(
  inner: unknown,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  // inner = [schemaVer, [ window, … ], boolFlag]
  const windows: unknown[] =
    Array.isArray((inner as unknown[] | null)?.[1]) ? (inner as unknown[])[1] as unknown[] : [];

  let shortWindow: WindowUsage | null = null;
  let longWindow: WindowUsage | null = null;

  for (const w of windows) {
    // index0 is *remaining* units (not cap) — unused for the bar; index1 is the
    // utilization fraction (used / cap, 0–1). See the header note.
    const utilFraction = num((w as unknown[])?.[1]);
    const periodType = num((w as unknown[])?.[2]);
    // Reset is in [[epochSec, nanos]] — we only need epochSec for the ISO timestamp.
    const resetSec = num(((w as unknown[])?.[3] as unknown[][])?.[0]?.[0]);

    const win: WindowUsage = {
      label: PERIOD_LABEL[periodType] ?? `Window ${periodType}`,
      // index1 is already used/cap as a 0–1 fraction — scale to the 0–100 the
      // Mac model expects. Clamp for display safety.
      utilization: Math.min(100, Math.max(0, Math.round(utilFraction * 100))),
      // resetSec === 0 means we couldn't parse it — leave resetsAt empty; callers
      // will render "–" or skip the countdown rather than showing epoch start.
      resetsAt: resetSec > 0 ? new Date(resetSec * 1000).toISOString() : '',
      windowDurationSec: periodType === 2 ? WEEK_SEC : FIVE_HOUR_SEC,
    };

    // Route by periodType: 1 → shortWindow (5h), 2 → longWindow (weekly).
    if (periodType === 2) {
      longWindow = win;
    } else {
      // Any non-2 periodType lands in shortWindow. periodType 1 is the only
      // confirmed value; future schema versions may add others — keep them here
      // rather than silently dropping them.
      shortWindow = win;
    }
  }

  return {
    provider: 'geminiConsumer',
    // Fallback shortWindow so the snapshot is always renderable even if the
    // RPC returns an empty windows array (e.g. account with no quota configured).
    shortWindow: shortWindow ?? {
      label: '5-Hour Window',
      utilization: 0,
      resetsAt: '',
      windowDurationSec: FIVE_HOUR_SEC,
    },
    longWindow,
    extras: {},
    // jSf9Qc carries no plan/tier field — the cap values in the live response
    // *could* be used to infer tier (Free=600, AI Plus=1200, …) but Google has
    // already shifted these twice since launch (May 17 → May 28), so we read
    // the live numbers rather than hardcoding a lookup table that will rot.
    // A manual override selector (like ChatGPT's) can be added in a follow-up.
    planLabel: 'Gemini',
    capturedAt: now,
    // Real numbers from the endpoint — not a local counter like ChatGPT.
    estimated: false,
  };
}

/** Safely coerce to a finite number; returns 0 for anything else. */
function num(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0;
}
