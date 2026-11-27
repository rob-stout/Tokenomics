/**
 * ChatGPT usage — EXACT (Codex allowance) first, local-counter fallback.
 *
 * The exact path reads /backend-api/wham/usage with an OAuth Bearer token from
 * the ChatGPT web session (/api/auth/session). That endpoint reports the Codex
 * allowance included with the plan (real used_percent + reset), NOT the chat
 * message cap, so its windows are labelled "Codex …". (Every other tracker missed this — they hit the cookie 401 and
 * settled for local counting.)
 *
 * The local counter (observe /backend-api/conversation, count against the quota
 * table) remains as a fallback for when the token/endpoint isn't available.
 *
 * This module: the exact reader + mapper, plan detection (/backend-api/me), the
 * fallback quota table, and snapshot derivation from a counter log.
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

// Stored values must stay backward compatible: 'pro' is the original $200 Pro
// tier, so the newer Pro tiers get their own ids ('prolite' $100, 'promax').
export type ChatGPTPlan =
  | 'free'
  | 'go'
  | 'plus'
  | 'prolite'
  | 'pro'
  | 'promax'
  | 'team'
  | 'business'
  | 'enterprise'
  | 'edu'
  | 'unknown';

interface MeResponse {
  // The /me response has historically shaped its plan info under different
  // keys (`account.plan`, `accounts.default.entitlement.plan_type`, etc.).
  // We probe a few plausible paths and accept the first hit.
  account?: { plan?: string; plan_type?: string };
  accounts?: Record<string, { entitlement?: { plan_type?: string } }>;
  plan?: string;
}

/**
 * The signed-in plan. /backend-api/me now answers cookie-only requests with an
 * anonymous profile (no plan), so read it from the web session first
 * (`account.planType`), then ask /me with the session's Bearer token.
 */
export async function detectChatGPTPlan(): Promise<ChatGPTPlan> {
  try {
    const sessionRes = await fetch('https://chatgpt.com/api/auth/session', { credentials: 'include' });
    if (!sessionRes.ok) return 'unknown';
    const session = (await sessionRes.json()) as { accessToken?: string; account?: { planType?: string } };
    const fromSession = canonicalPlan(session.account?.planType);
    if (fromSession !== 'unknown' || !session.accessToken) return fromSession;

    const res = await fetch('https://chatgpt.com/backend-api/me', {
      credentials: 'include',
      headers: { Authorization: `Bearer ${session.accessToken}` },
    });
    if (!res.ok) return 'unknown';
    const data = (await res.json()) as MeResponse;
    return canonicalPlan(extractPlan(data));
  } catch {
    return 'unknown';
  }
}

function extractPlan(data: MeResponse): string | undefined {
  if (data.plan) return data.plan;
  if (data.account?.plan_type) return data.account.plan_type;
  if (data.account?.plan) return data.account.plan;
  if (data.accounts) {
    for (const acc of Object.values(data.accounts)) {
      const pt = acc.entitlement?.plan_type;
      if (pt) return pt;
    }
  }
  return undefined;
}

/** Map OpenAI's `plan_type` strings to our plan ids. Exported for tests. */
export function canonicalPlan(raw: string | undefined): ChatGPTPlan {
  if (!raw) return 'unknown';
  const s = raw.toLowerCase().replace(/^chatgpt_/, '');
  if (s === 'free') return 'free';
  if (s === 'go') return 'go';
  if (s === 'plus') return 'plus';
  if (s === 'prolite') return 'prolite';
  if (s === 'pro') return 'pro';
  if (s === 'promax') return 'promax';
  if (s === 'team') return 'team';
  if (s === 'business' || s.startsWith('self_serve_business')) return 'business';
  if (s.startsWith('enterprise')) return 'enterprise';
  if (s.startsWith('edu')) return 'edu';
  return 'unknown';
}

// ── Exact path: /backend-api/wham/usage via the web session's Bearer token ──

interface WhamWindow {
  used_percent?: number;
  limit_window_seconds?: number;
  reset_after_seconds?: number;
  reset_at?: number; // unix SECONDS
}

export interface WhamUsageResponse {
  plan_type?: string;
  rate_limit?: {
    primary_window?: WhamWindow | null;
    secondary_window?: WhamWindow | null;
  } | null;
}

/** The web session's OAuth access token (same one the ChatGPT app uses). */
async function fetchSessionAccessToken(): Promise<string | null> {
  try {
    const res = await fetch('https://chatgpt.com/api/auth/session', { credentials: 'include' });
    if (!res.ok) return null;
    const data = (await res.json()) as { accessToken?: string };
    return data.accessToken ?? null;
  } catch {
    return null;
  }
}

/**
 * Exact ChatGPT usage from /wham/usage. Returns null on ANY failure (no token,
 * non-200, unexpected shape) so the caller falls back to the local counter.
 */
export async function fetchExactChatGPTSnapshot(
  now: number = Date.now(),
): Promise<ProviderUsageSnapshot | null> {
  const token = await fetchSessionAccessToken();
  if (!token) return null;
  try {
    const res = await fetch('https://chatgpt.com/backend-api/wham/usage', {
      credentials: 'include',
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return null;
    const data = (await res.json()) as WhamUsageResponse;
    return mapWhamUsageToSnapshot(data, now);
  } catch {
    return null;
  }
}

/**
 * Pure mapper (unit-tested): /wham/usage response → snapshot, `estimated: false`.
 *
 * IMPORTANT: this endpoint is the Codex allowance included with the ChatGPT
 * plan (openai/codex rate_limit_status_payload.rs), not the chat message cap.
 * Windows are classified by their length, not by the primary/secondary slot:
 * a weekly window can be the primary one. The shortest window becomes the
 * short window and the longest (if two) the long window. Each window's
 * label starts with "Codex" so nobody reads it as a chat limit.
 * Returns null if no window is usable so the caller can fall back.
 */
export function mapWhamUsageToSnapshot(
  data: WhamUsageResponse,
  now: number = Date.now(),
): ProviderUsageSnapshot | null {
  const windows = [data.rate_limit?.primary_window, data.rate_limit?.secondary_window]
    .filter((w): w is WhamWindow => !!w && typeof w.used_percent === 'number')
    .map((w) => whamWindow(w, now))
    .sort((a, b) => a.windowDurationSec - b.windowDurationSec);
  const shortWindow = windows[0];
  if (!shortWindow) return null;
  const longWindow = windows.length > 1 ? windows[windows.length - 1]! : null;

  return {
    provider: 'chatgpt',
    shortWindow,
    longWindow,
    extras: {},
    planLabel: planDisplay(canonicalPlan(data.plan_type)),
    capturedAt: now,
    estimated: false,
  };
}

const CODEX_PREFIX = 'Codex';

function whamWindow(w: WhamWindow, now: number): WindowUsage {
  const durationSec = w.limit_window_seconds ?? 0;
  const resetMs = w.reset_at
    ? w.reset_at * 1000
    : w.reset_after_seconds
      ? now + w.reset_after_seconds * 1000
      : now + durationSec * 1000;
  return {
    // "Codex" goes in the label (not a sublabel) so the Mac keeps computing the
    // live countdown from resetsAt instead of freezing a baked-in string.
    label: `${CODEX_PREFIX} ${whamWindowLabel(durationSec)}`,
    utilization: Math.min(100, Math.max(0, Math.round(w.used_percent ?? 0))),
    resetsAt: new Date(resetMs).toISOString(),
    windowDurationSec: durationSec,
  };
}

/** Human label derived from the window length OpenAI reports. */
function whamWindowLabel(durationSec: number): string {
  const hours = durationSec / 3600;
  if (hours <= 1.5) return 'Hourly';
  if (hours <= 6.5) return `${Math.round(hours)}-Hour Window`;
  if (durationSec >= 6 * 86400 && durationSec <= 8 * 86400) return 'Weekly';
  if (durationSec >= 28 * 86400) return 'Monthly';
  return `${Math.round(durationSec / 86400)}-Day Window`;
}

// ── Quota table (May 2026; Plus/Pro/Team only) ───────────────
// Values are documented OpenAI defaults. They shift quarterly — a routine
// monthly check is configured outside this file to flag changes.
//
// Modeling choice: one "short window" per plan covers the dominant cap
// (GPT-5 messages). For Plus/Pro we surface a second window for the
// weekly Thinking budget. Free has no secondary window.

interface PlanQuota {
  shortWindowSec: number;
  shortWindowLimit: number;
  shortWindowLabel: string;
  longWindowSec?: number;
  longWindowLimit?: number;
  longWindowLabel?: string;
}

const QUOTA: Partial<Record<ChatGPTPlan, PlanQuota>> = {
  plus: {
    shortWindowSec: 3 * 3600,
    shortWindowLimit: 160,
    shortWindowLabel: '3-Hour Window',
    longWindowSec: 7 * 86400,
    longWindowLimit: 3000,
    longWindowLabel: 'Weekly Thinking',
  },
  pro: {
    // ChatGPT Pro ($200/mo) is effectively uncapped on GPT-5.x per
    // OpenAI's published behaviour (May 2026). We carry a very high
    // sentinel so the bar shows a tiny utilization rather than misleading
    // the user with a low cap. The count is still informational.
    shortWindowSec: 3 * 3600,
    shortWindowLimit: 5000,
    shortWindowLabel: '3-Hour Window',
    longWindowSec: 7 * 86400,
    longWindowLimit: 15000,
    longWindowLabel: 'Weekly Thinking',
  },
  team: {
    shortWindowSec: 3 * 3600,
    shortWindowLimit: 160,
    shortWindowLabel: '3-Hour Window',
    longWindowSec: 7 * 86400,
    longWindowLimit: 3000,
    longWindowLabel: 'Weekly Thinking',
  },
};

function quotaFor(plan: ChatGPTPlan): PlanQuota | null {
  switch (plan) {
    case 'plus':
      return QUOTA.plus ?? null;
    case 'pro':
    case 'prolite':
    case 'promax':
      return QUOTA.pro ?? null;
    case 'team':
    case 'business':
      return QUOTA.team ?? null;
    // No published message cap to count against (free/go unlimited; enterprise,
    // edu and unknown vary by contract).
    default:
      return null;
  }
}

/** A timestamped message log entry. Persisted in chrome.storage.local. */
export interface ChatGPTMessageEvent {
  ts: number; // Unix ms when the conversation POST was observed
  model: string | null;
}

const THINKING_MODELS = new Set([
  'gpt-5-thinking',
  'gpt-5-thinking-pro',
  'gpt-5.2-thinking',
  'o1',
  'o1-pro',
  'o3',
  'o3-pro',
  'o4-mini',
]);

function isThinking(model: string | null): boolean {
  if (!model) return false;
  const s = model.toLowerCase();
  if (THINKING_MODELS.has(s)) return true;
  return s.includes('thinking') || s.startsWith('o1') || s.startsWith('o3');
}

/**
 * Local-counter estimate. Returns null when there is no meaningful message cap
 * to count against: Free and Go have unlimited everyday chat (the old
 * 10-per-5-hours table is gone), and unknown plans have no table at all.
 */
export function deriveSnapshot(
  events: ChatGPTMessageEvent[],
  plan: ChatGPTPlan,
  now: number = Date.now(),
): ProviderUsageSnapshot | null {
  const quota = quotaFor(plan);
  if (!quota) return null;

  const shortWindowMs = quota.shortWindowSec * 1000;
  const shortCount = events.filter((e) => now - e.ts <= shortWindowMs).length;
  const shortUtil = quota.shortWindowLimit > 0
    ? Math.min(100, Math.round((shortCount / quota.shortWindowLimit) * 100))
    : 0;

  // Reset time approximation: the oldest still-in-window event drops out
  // first. If no events, the window is wide open right now.
  const oldestInWindow = events.find((e) => now - e.ts <= shortWindowMs);
  const shortResetMs = oldestInWindow ? oldestInWindow.ts + shortWindowMs : now + shortWindowMs;

  const shortWindow: WindowUsage = {
    label: quota.shortWindowLabel,
    utilization: shortUtil,
    resetsAt: new Date(shortResetMs).toISOString(),
    windowDurationSec: quota.shortWindowSec,
    sublabelOverride: formatCounterSublabel(shortCount, quota.shortWindowLimit, 'msgs', shortResetMs, now),
  };

  let longWindow: WindowUsage | null = null;
  if (quota.longWindowSec && quota.longWindowLimit && quota.longWindowLabel) {
    const longWindowMs = quota.longWindowSec * 1000;
    const longEvents = events.filter(
      (e) => isThinking(e.model) && now - e.ts <= longWindowMs,
    );
    const longCount = longEvents.length;
    const longUtil = Math.min(100, Math.round((longCount / quota.longWindowLimit) * 100));
    const oldestThinkingInWindow = longEvents[0];
    const longResetMs = oldestThinkingInWindow
      ? oldestThinkingInWindow.ts + longWindowMs
      : now + longWindowMs;

    longWindow = {
      label: quota.longWindowLabel,
      utilization: longUtil,
      resetsAt: new Date(longResetMs).toISOString(),
      windowDurationSec: quota.longWindowSec,
      sublabelOverride: formatCounterSublabel(longCount, quota.longWindowLimit, 'thinking msgs', longResetMs, now),
    };
  }

  return {
    provider: 'chatgpt',
    shortWindow,
    longWindow,
    extras: {},
    planLabel: planDisplay(plan),
    capturedAt: now,
    estimated: true,
  };
}

function formatCounterSublabel(
  count: number,
  limit: number,
  noun: string,
  resetMs: number,
  now: number,
): string {
  const reset = formatResetCompact(resetMs, now);
  return reset ? `${count} of ${limit} ${noun} · ${reset}` : `${count} of ${limit} ${noun}`;
}

function formatResetCompact(resetMs: number, now: number): string {
  const remainingMs = resetMs - now;
  if (remainingMs <= 0) return 'resets now';
  const totalMinutes = Math.floor(remainingMs / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours >= 24) return `resets in ${Math.floor(hours / 24)}d`;
  if (hours > 0) return `resets in ${hours}h ${minutes}m`;
  return `resets in ${minutes}m`;
}

export function planDisplay(plan: ChatGPTPlan): string {
  switch (plan) {
    case 'free':
      return 'Free';
    case 'go':
      return 'Go';
    case 'plus':
      return 'Plus';
    case 'prolite':
      return 'Pro 100';
    case 'pro':
      return 'Pro 200';
    case 'promax':
      return 'Pro 500';
    case 'team':
      return 'Team';
    case 'business':
      return 'Business';
    case 'enterprise':
      return 'Enterprise';
    case 'edu':
      return 'Edu';
    case 'unknown':
      return '';
  }
}

/** Prune events older than the longest tracked window (weekly = 7d). */
export function pruneEvents(events: ChatGPTMessageEvent[], now: number = Date.now()): ChatGPTMessageEvent[] {
  const cutoff = now - 7 * 86400 * 1000;
  return events.filter((e) => e.ts >= cutoff);
}
