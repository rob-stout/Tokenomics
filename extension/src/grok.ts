/**
 * Grok usage reader.
 *
 * Two paths, chosen by GET https://grok.com/rest/subscriptions:
 *   - Paid (an ACTIVE subscription): one weekly credit pool read from the
 *     gRPC-web call GrokBuildBilling/GetGrokCreditsConfig (protobuf, decoded by
 *     the small reader below). Same data as grok.com Settings > Usage.
 *   - Free: the fast-query counter from /rest/rate-limits, described next.
 *
 * Free path: polls https://grok.com/rest/rate-limits from the service worker via a POST
 * with `credentials: 'include'` (cookie auth). Confirmed working without any
 * anti-bot headers — session cookies from a logged-in grok.com tab are sent
 * automatically by the browser.
 *
 * Billing unit: fast queries per rolling 24-hour window.
 *   utilization% = (totalQueries - remainingQueries) / totalQueries * 100
 *
 * Real response (2026-06-01):
 *   { "windowSizeSeconds": 86400, "remainingQueries": 20, "totalQueries": 20,
 *     "lowEffortRateLimits": null, "highEffortRateLimits": null }
 *
 * The window is rolling — there is no absolute reset timestamp. We approximate
 * resetsAt as now + windowSizeSeconds, which gives the UI a sensible countdown.
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

const RATE_LIMITS_URL = 'https://grok.com/rest/rate-limits';
const DEFAULT_WINDOW_SEC = 86400; // 24h rolling window

export class AuthError extends Error {
  constructor(status: number) {
    super(`Not signed in to grok.com (status ${status})`);
    this.name = 'AuthError';
  }
}

export class RateLimitError extends Error {
  constructor() {
    super('grok.com rate limited the request');
    this.name = 'RateLimitError';
  }
}

const SUBSCRIPTIONS_URL = 'https://grok.com/rest/subscriptions';
const CREDITS_URL = 'https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig';
const WEEK_SEC = 7 * 86400;

// ── Response shape (confirmed against live API 2026-06-01) ───

interface RateLimitsResponse {
  windowSizeSeconds?: number;
  remainingQueries?: number;
  totalQueries?: number;
  // lowEffortRateLimits / highEffortRateLimits present but null on Free — ignored.
}

// ── Subscription detection ────────────────────────────────────

interface SubscriptionsResponse {
  subscriptions?: Array<{ tier?: string; status?: string; createTime?: string }> | null;
  dominantPlan?: { surfaceNames?: Record<string, string> | null } | null;
}

export interface GrokPlanInfo {
  /** An ACTIVE subscription exists, so the weekly credit pool applies. */
  paid: boolean;
  /** Display name for the popup; '' when unknown. */
  planLabel: string;
}

// Tier enums seen in the wild (ceiling, vibe-bar sources) → names grok.com shows.
const TIER_NAMES: Record<string, string> = {
  SUBSCRIPTION_TIER_SUPER_GROK_PRO: 'SuperGrok Heavy',
  SUBSCRIPTION_TIER_GROK_PRO: 'SuperGrok',
  SUBSCRIPTION_TIER_SUPER_GROK_LITE: 'SuperGrok Lite',
  SUBSCRIPTION_TIER_X_PREMIUM_PLUS: 'X Premium+',
  SUBSCRIPTION_TIER_X_PREMIUM: 'X Premium',
  SUBSCRIPTION_TIER_X_BASIC: 'X Basic',
};

const ACTIVE_STATUS = 'SUBSCRIPTION_STATUS_ACTIVE';

/** Pure (exported for tests): /rest/subscriptions → paid flag + plan label. */
export function parseSubscriptions(raw: SubscriptionsResponse): GrokPlanInfo {
  const active = (raw.subscriptions ?? [])
    .filter((s) => s.status === ACTIVE_STATUS)
    // Several can be active mid-switch; the newest is the plan the user chose.
    .sort((a, b) => (b.createTime ?? '').localeCompare(a.createTime ?? ''));
  const top = active[0];
  if (!top) return { paid: false, planLabel: '' };

  // SURFACE_DISPLAY is the name xAI shows for the plan; the tier enum keeps its
  // pre-bundle name after a plan move, so it is only the fallback.
  const display = raw.dominantPlan?.surfaceNames?.['SURFACE_DISPLAY']?.trim();
  const planLabel = display || (top.tier ? (TIER_NAMES[top.tier] ?? '') : '');
  return { paid: true, planLabel };
}

/** null = couldn't tell (network/shape); the caller then uses the free path. */
async function fetchPlanInfo(): Promise<GrokPlanInfo | null> {
  try {
    const res = await fetch(SUBSCRIPTIONS_URL, { credentials: 'include' });
    if (res.status === 401 || res.status === 403) throw new AuthError(res.status);
    if (!res.ok) return null;
    return parseSubscriptions((await res.json()) as SubscriptionsResponse);
  } catch (err) {
    if (err instanceof AuthError) throw err;
    return null;
  }
}

// ── Paid weekly pool: gRPC-web + protobuf ─────────────────────

type ProtoValue = number | Uint8Array;
type ProtoFields = Map<number, ProtoValue[]>;

/**
 * Minimal protobuf reader: varint (0), fixed32 as float32 (5), length-delimited
 * (2); fixed64 is skipped. Stops quietly on anything malformed. Exported for tests.
 */
export function decodeProto(bytes: Uint8Array): ProtoFields {
  const out: ProtoFields = new Map();
  let at = 0;

  const varint = (): number => {
    let value = 0;
    let scale = 1;
    while (at < bytes.length) {
      const byte = bytes[at++]!;
      value += (byte & 0x7f) * scale;
      if (!(byte & 0x80)) break;
      scale *= 128;
    }
    return value;
  };
  const push = (field: number, v: ProtoValue) => {
    const list = out.get(field);
    if (list) list.push(v);
    else out.set(field, [v]);
  };

  while (at < bytes.length) {
    const key = varint();
    const field = Math.floor(key / 8);
    const wire = key & 7;
    if (!field) break;

    if (wire === 0) {
      push(field, varint());
    } else if (wire === 2) {
      const len = varint();
      if (at + len > bytes.length) break;
      push(field, bytes.subarray(at, at + len));
      at += len;
    } else if (wire === 5) {
      if (at + 4 > bytes.length) break;
      push(field, new DataView(bytes.buffer, bytes.byteOffset + at, 4).getFloat32(0, true));
      at += 4;
    } else if (wire === 1) {
      at += 8;
    } else {
      break;
    }
  }
  return out;
}

function firstNumber(fields: ProtoFields, n: number): number | undefined {
  const v = fields.get(n)?.[0];
  return typeof v === 'number' ? v : undefined;
}

function firstBytes(fields: ProtoFields, n: number): Uint8Array | undefined {
  const v = fields.get(n)?.[0];
  return v instanceof Uint8Array ? v : undefined;
}

/** gRPC-web framing: 5-byte header (flag, u32 length) then the message. Trailer frames have the 0x80 flag. */
export function firstGrpcDataFrame(bytes: Uint8Array): Uint8Array | null {
  let at = 0;
  while (at + 5 <= bytes.length) {
    const flag = bytes[at]!;
    const len = new DataView(bytes.buffer, bytes.byteOffset + at + 1, 4).getUint32(0, false);
    const body = bytes.subarray(at + 5, at + 5 + len);
    at += 5 + len;
    if ((flag & 0x80) === 0) return body;
  }
  return null;
}

// Only the enums two independent sources agree on; the rest disagree.
const PRODUCT_NAMES: Record<number, string> = { 2: 'Grok Build', 4: 'Chat' };

export interface GrokPool {
  /** 0–100. proto3 omits zeros, so a missing field is a genuine 0%. */
  usedPercent: number;
  /** ms epoch of the pool's period end, when present. */
  resetAtMs: number | null;
  /** Per-product percent, known products only. */
  products: Array<{ name: string; percent: number }>;
}

/**
 * Pure (exported for tests): decoded GetGrokCreditsConfig message → pool.
 * Layout: message field 1 = config { 1: pool percent (float), 5: period end
 * Timestamp {1: seconds}, 7*: {1: product enum, 2: percent (float)} }.
 * Returns null when nothing recognisable decodes (schema drift), so we never
 * show a made-up healthy 0%.
 */
export function parseCreditsMessage(message: Uint8Array): GrokPool | null {
  const configBytes = firstBytes(decodeProto(message), 1);
  if (!configBytes) return null;
  const config = decodeProto(configBytes);

  let resetAtMs: number | null = null;
  const periodEnd = firstBytes(config, 5);
  if (periodEnd) {
    const seconds = firstNumber(decodeProto(periodEnd), 1);
    if (seconds !== undefined && Number.isFinite(seconds) && seconds > 0) resetAtMs = seconds * 1000;
  }

  const productEntries = config.get(7) ?? [];
  const products: GrokPool['products'] = [];
  for (const entry of productEntries) {
    if (!(entry instanceof Uint8Array)) continue;
    const fields = decodeProto(entry);
    const id = firstNumber(fields, 1);
    const name = id !== undefined ? PRODUCT_NAMES[id] : undefined;
    if (name) products.push({ name, percent: firstNumber(fields, 2) ?? 0 });
  }

  const used = firstNumber(config, 1);
  if (used === undefined && resetAtMs === null && productEntries.length === 0) return null;
  return {
    usedPercent: Math.min(100, Math.max(0, used !== undefined && Number.isFinite(used) ? used : 0)),
    resetAtMs,
    products,
  };
}

async function fetchCreditsPool(): Promise<GrokPool | null> {
  const res = await fetch(CREDITS_URL, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/grpc-web+proto', 'X-Grpc-Web': '1' },
    body: new Uint8Array(5),
  });
  if (res.status === 401 || res.status === 403) throw new AuthError(res.status);
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) return null;
  const frame = firstGrpcDataFrame(new Uint8Array(await res.arrayBuffer()));
  return frame ? parseCreditsMessage(frame) : null;
}

/** Pure (exported for tests): weekly pool → snapshot with one "Weekly" window. */
export function mapPoolToSnapshot(
  pool: GrokPool,
  planLabel: string,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  return {
    provider: 'grok',
    shortWindow: {
      label: 'Weekly',
      utilization: Math.round(pool.usedPercent),
      // '' (no period end decoded) is honest; the bridge skips snapshots with no reset.
      resetsAt: pool.resetAtMs !== null ? new Date(pool.resetAtMs).toISOString() : '',
      windowDurationSec: WEEK_SEC,
    },
    longWindow: null,
    extras: {},
    planLabel: planLabel || 'Grok',
    capturedAt: now,
    estimated: false,
  };
}

// ── Fetch layer ───────────────────────────────────────────────

async function fetchRateLimits(): Promise<RateLimitsResponse> {
  const res = await fetch(RATE_LIMITS_URL, {
    method: 'POST',
    credentials: 'include',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ modelName: 'fast' }),
  });

  if (res.status === 401 || res.status === 403) throw new AuthError(res.status);
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`grok rate-limits fetch failed: ${res.status}`);

  return (await res.json()) as RateLimitsResponse;
}

// ── Public API ────────────────────────────────────────────────

/**
 * Fetch Grok fast-query usage using the web session cookie.
 */
export async function fetchGrokUsage(): Promise<ProviderUsageSnapshot> {
  const plan = await fetchPlanInfo();
  if (plan?.paid) {
    const pool = await fetchCreditsPool().catch((err: unknown) => {
      if (err instanceof AuthError || err instanceof RateLimitError) throw err;
      return null;
    });
    if (pool) return mapPoolToSnapshot(pool, plan.planLabel, Date.now());
    // Credits call failed or didn't decode: fall through to the query counter.
  }
  const raw = await fetchRateLimits();
  // Confirmed no active subscription → say Free; unknown stays "Grok".
  return mapToSnapshot(raw, Date.now(), plan && !plan.paid ? 'Free' : plan?.planLabel || 'Grok');
}

/**
 * Pure mapper from a RateLimitsResponse to a ProviderUsageSnapshot.
 * Exported for unit testing.
 *
 * @param raw - The parsed JSON from /rest/rate-limits.
 * @param now - Current time in milliseconds (injectable for tests).
 */
export function mapToSnapshot(
  raw: RateLimitsResponse,
  now: number = Date.now(),
  planLabel: string = 'Grok',
): ProviderUsageSnapshot {
  const total = num(raw.totalQueries);
  const remaining = num(raw.remainingQueries);
  const windowSec = num(raw.windowSizeSeconds) || DEFAULT_WINDOW_SEC;

  // Avoid divide-by-zero when totalQueries is 0 (no plan / unexpected response).
  const used = Math.max(0, total - remaining);
  const utilization =
    total > 0 ? Math.min(100, Math.max(0, Math.round((used / total) * 100))) : 0;

  // Rolling window — no absolute reset timestamp from the API.
  // Approximate as now + windowSizeSeconds so the UI shows a sensible countdown.
  const resetsAt = new Date(now + windowSec * 1000).toISOString();

  const shortWindow: WindowUsage = {
    label: 'Fast Queries',
    utilization,
    resetsAt,
    windowDurationSec: windowSec,
    sublabelOverride: `${remaining} of ${total} left`,
  };

  return {
    provider: 'grok',
    shortWindow,
    longWindow: null,
    extras: {},
    planLabel,
    capturedAt: now,
    estimated: false,
  };
}

// ── Helpers ───────────────────────────────────────────────────

/** Safely coerce an unknown value to a finite number; returns 0 otherwise. */
function num(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const parsed = parseFloat(v);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}
