import type { ProviderUsageSnapshot, UsageCredits, WindowUsage } from './snapshot';

const FIVE_HOUR_SEC = 5 * 3600;
const SEVEN_DAY_SEC = 7 * 86400;

// Pure parsing lives here (no extension APIs) so it can be unit-tested in node.

// ── Response shapes (captured live 2026-11-25) ──────────────

export interface ClaudeOrg {
  uuid?: string;
  capabilities?: string[];
  rate_limit_tier?: string | null;
  analytics_subscription_plan?: string | null;
}

interface UsageWindow {
  utilization: number;
  resets_at: string;
}

interface LimitEntry {
  kind?: string;
  percent?: number;
  resets_at?: string | null;
  scope?: { model?: { display_name?: string | null } | null } | null;
  // Money-shaped entries (dollar promo windows) are not usage windows.
  limit_dollars?: unknown;
  used_dollars?: unknown;
}

interface Money {
  amount_minor?: number;
  currency?: string;
  exponent?: number;
}

export interface UsageResponse {
  five_hour?: UsageWindow | null;
  seven_day?: UsageWindow | null;
  seven_day_opus?: UsageWindow | null;
  limits?: LimitEntry[] | null;
  extra_usage?: {
    is_enabled?: boolean;
    used_credits?: number | null;
    monthly_limit?: number | null;
    currency?: string | null;
    decimal_places?: number | null;
  } | null;
  spend?: {
    enabled?: boolean;
    used?: Money | null;
    limit?: Money | null;
  } | null;
}

// ── Org selection ───────────────────────────────────────────

const CHAT_CAPABILITIES = ['chat', 'claude_max', 'claude_pro'];

/**
 * /api/organizations can list several orgs; an API-only org (index 0 for some
 * accounts) 403s on /usage. Take the first org that can chat. Exported for tests.
 */
export function pickChatOrg(orgs: unknown): ClaudeOrg | null {
  if (!Array.isArray(orgs)) return null;
  for (const org of orgs as ClaudeOrg[]) {
    if (!org || typeof org.uuid !== 'string') continue;
    const caps = Array.isArray(org.capabilities) ? org.capabilities : [];
    if (caps.some((c) => CHAT_CAPABILITIES.includes(c))) return org;
  }
  return null;
}

/** Plan name from the org's tier / capabilities; '' when unrecognised. Exported for tests. */
export function planFromOrg(org: ClaudeOrg): string {
  const tier = (org.rate_limit_tier ?? '').toLowerCase();
  const caps = Array.isArray(org.capabilities) ? org.capabilities : [];
  const analytics = (org.analytics_subscription_plan ?? '').toLowerCase();

  if (tier.includes('ultra') || tier.includes('max_20x')) return 'Ultra';
  if (tier.includes('max')) return 'Max';
  if (caps.includes('claude_max') || analytics.includes('claude_max')) {
    return analytics.includes('20x') ? 'Ultra' : 'Max';
  }
  if (caps.includes('claude_pro') || analytics.includes('claude_pro') || tier.includes('claude_pro')) {
    return 'Pro';
  }
  // default_claude_ai is also the free tier, so only call it Pro when
  // capabilities don't say otherwise (older responses had no capabilities).
  if (tier === 'default_claude_ai' && caps.length === 0) return 'Pro';
  return '';
}

// ── Mapping ─────────────────────────────────────────────────

/** Exported for tests. */
export function mapToSnapshot(
  usage: UsageResponse,
  planLabel: string,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  const limits = usableLimits(usage.limits);
  const session = limits.find((l) => l.kind === 'session');
  const weeklyAll = limits.find((l) => l.kind === 'weekly_all');

  // limits[] is the current shape; five_hour / seven_day are the fallback.
  const fiveHour =
    (session && fromLimit('5-Hour Window', session, FIVE_HOUR_SEC)) ||
    makeWindow('5-Hour Window', usage.five_hour, FIVE_HOUR_SEC);
  const sevenDay =
    (weeklyAll && fromLimit('7-Day Window', weeklyAll, SEVEN_DAY_SEC)) ||
    makeWindow('7-Day Window', usage.seven_day, SEVEN_DAY_SEC);

  // Plans without a session limit (Ultra) have no 5-hour window at all —
  // promote the weekly one rather than invent a 0% session bar.
  const shortWindow = fiveHour ?? sevenDay;
  if (!shortWindow) throw new Error('claude usage response had no usage windows');
  const longWindow = fiveHour ? sevenDay : null;

  const extras: ProviderUsageSnapshot['extras'] = {};
  const scoped = limits
    .filter((l) => l.kind === 'weekly_scoped')
    .map((l) => {
      const name = l.scope?.model?.display_name?.trim();
      return fromLimit(name ? `${name} Weekly` : 'Model Weekly', l, SEVEN_DAY_SEC);
    })
    .filter((w): w is WindowUsage => w !== null);
  if (scoped.length > 0) extras.scopedWeekly = scoped;

  // Legacy per-model key, only if the new limits[] list isn't there.
  if (limits.length === 0) {
    const opus = makeWindow('Opus 7-Day', usage.seven_day_opus, SEVEN_DAY_SEC);
    if (opus) extras.opusSevenDay = opus;
  }

  const credits = mapUsageCredits(usage);
  if (credits) extras.usageCredits = credits;

  return {
    provider: 'claude',
    shortWindow,
    longWindow,
    extras,
    planLabel,
    capturedAt: now,
  };
}

/** Drop non-usage entries: money objects and anything without a numeric percent. */
function usableLimits(raw: UsageResponse['limits']): LimitEntry[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (l) =>
      l &&
      typeof l.percent === 'number' &&
      l.limit_dollars === undefined &&
      l.used_dollars === undefined,
  );
}

function fromLimit(label: string, l: LimitEntry, durationSec: number): WindowUsage | null {
  if (typeof l.percent !== 'number') return null;
  return {
    label,
    utilization: Math.max(0, l.percent),
    resetsAt: l.resets_at ?? '',
    windowDurationSec: durationSec,
  };
}

function makeWindow(
  label: string,
  raw: UsageWindow | null | undefined,
  durationSec: number,
): WindowUsage | null {
  if (!raw || typeof raw.utilization !== 'number') return null;
  return {
    label,
    // claude.ai's /usage endpoint returns utilization already as a percentage
    // (0–100, e.g. `7` for 7%) — the plan doc's `0.36` example was wrong.
    // No multiplier; just guard against negative and absurd values.
    utilization: Math.max(0, raw.utilization),
    resetsAt: raw.resets_at,
    windowDurationSec: durationSec,
  };
}

// ── Usage credits (Anthropic's name for extra usage) ────────

function moneyToMajor(m: Money | null | undefined): number | null {
  if (!m || typeof m.amount_minor !== 'number') return null;
  return m.amount_minor / Math.pow(10, m.exponent ?? 2);
}

function mapUsageCredits(usage: UsageResponse): UsageCredits | undefined {
  const spend = usage.spend;
  if (spend?.enabled === true) {
    const used = moneyToMajor(spend.used);
    if (used !== null) {
      return {
        used,
        limit: moneyToMajor(spend.limit),
        currency: spend.used?.currency ?? 'USD',
      };
    }
  }

  const extra = usage.extra_usage;
  if (extra?.is_enabled === true && typeof extra.used_credits === 'number') {
    const scale = Math.pow(10, extra.decimal_places ?? 2);
    return {
      used: extra.used_credits / scale,
      limit: typeof extra.monthly_limit === 'number' ? extra.monthly_limit / scale : null,
      currency: extra.currency ?? 'USD',
    };
  }
  return undefined;
}
