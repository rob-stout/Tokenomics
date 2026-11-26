/**
 * Leonardo.ai usage reader.
 *
 * Auth: Auth0 access token (Bearer) + `x-leo-schema-version: latest` header.
 *
 * ── HOW THE TOKEN IS OBTAINED ────────────────────────────────────────────────
 * Leonardo migrated from AWS Cognito to Auth0. The access token is no longer
 * stored in localStorage — Auth0 keeps it purely in page memory (a closure
 * inside the SDK). It is captured by a MAIN-world content script
 * (`content/leonardo-main.ts`) that wraps window.fetch and observes the token
 * off the page's own outgoing requests to api.leonardo.ai/v1/graphql. The
 * ISOLATED relay (`content/leonardo-watch.ts`) forwards it to the service
 * worker via `{ kind: 'LEONARDO_TOKEN' }`. The SW caches it and passes it
 * here for the GraphQL call.
 *
 * ── API ───────────────────────────────────────────────────────────────────────
 * POST https://api.leonardo.ai/v1/graphql
 * Headers: Authorization: Bearer <idToken>, x-leo-schema-version: latest
 * Body: GetUserTokensFromSub GraphQL query (confirmed live 2026-06-11)
 *
 * ── RESPONSE SHAPE ───────────────────────────────────────────────────────────
 * Real response (Free plan, 2026-06-11):
 *   { "data": { "user_details": [
 *     { "plan": "FREE", "subscriptionTokens": 150, "paidTokens": 0,
 *       "rolloverTokens": 0, "tokenRenewalDate": "..." }
 *   ] } }
 *
 * NOTE: `user_details` is now a ROOT field (not nested under `users`).
 * `$sub` is the cognitoId (the user's UUID identity, unchanged across the
 * Cognito→Auth0 migration — just the auth token delivery mechanism changed).
 *
 * Billing unit: tokens (daily — Free = 150/day, paid plans vary).
 * Utilization is computed from a plan→cap table (see PLAN_CAPS below) because
 * the API returns tokens *remaining* but no cap.
 *
 * ── API KEY PATH (optional, preferred) ───────────────────────────────────────
 * With a user-pasted API key the reader calls the official REST endpoint
 *   GET https://cloud.leonardo.ai/api/rest/v1/me   (Authorization: Bearer <key>)
 * which returns `{ user_details: [{ subscriptionTokens, paidTokens,
 * subscriptionGptTokens, subscriptionModelTokens, apiSubscriptionTokens,
 * tokenRenewalDate, user: { id, username } }] }` (field list from Leonardo's
 * official SDK models for getUserSelf).
 *
 * DIFFERENCES vs the web GraphQL path (see mapMeToSnapshot):
 *  - /me has NO `plan` and NO `rolloverTokens`, so the plan→cap table cannot be
 *    applied: utilization is not derivable and is reported as 0 (same as the
 *    existing unknown-plan behavior). The honest number is "N tokens left".
 *  - tokens left = subscriptionTokens + paidTokens (rollover is not exposed;
 *    it is likely folded into those balances, unverified).
 *  - The GPT / model / API pools are separate and excluded, as before.
 *
 * NOTE: `apiCredit` / `apiSubscriptionTokens` fields are a SEPARATE developer-API
 * pool and are intentionally excluded from this reader.
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';
import type { RenewalPoll } from './renewal';

const GRAPHQL_URL = 'https://api.leonardo.ai/v1/graphql';
const DAY_SEC = 86400;
const ME_URL = 'https://cloud.leonardo.ai/api/rest/v1/me';

// Per-plan token caps for the utilization ring. The Leonardo API returns
// tokens *remaining* but no cap, so we map the plan to its known allotment.
// Free is confirmed live (150/day); paid tiers are the published monthly
// allotments. Verified 2026-06-11: Free=150, Apprentice=8,500, Artisan=25,000,
// Maestro=60,000.
// Leonardo renamed the paid plans (Essential / Premium / Ultimate) with the same
// allotments; both generations of names are accepted.
const PLAN_CAPS: Record<string, number> = {
  FREE: 150,
  APPRENTICE: 8500,
  ARTISAN: 25000,
  MAESTRO: 60000,
  ESSENTIAL: 8500,
  PREMIUM: 25000,
  ULTIMATE: 60000,
};

/** Look up the token cap for a plan slug (handles "_V2" suffixes). Returns 0 when unknown. */
function capForPlan(plan: string | undefined): number {
  if (!plan) return 0;
  const base = plan.trim().toUpperCase().split('_')[0]; // "APPRENTICE_V2" -> "APPRENTICE"
  return PLAN_CAPS[base] ?? 0;
}

export class AuthError extends Error {
  constructor(status: number, viaApiKey = false) {
    super(
      viaApiKey
        ? `Leonardo rejected the API key (status ${status}). Check that it is correct.`
        : `Not signed in to leonardo.ai (status ${status})`,
    );
    this.name = 'AuthError';
  }
}

export class RateLimitError extends Error {
  constructor() {
    super('api.leonardo.ai rate limited the request');
    this.name = 'RateLimitError';
  }
}

// ── GraphQL response shapes ───────────────────────────────────

interface UserDetails {
  plan?: string;
  subscriptionTokens?: number;
  paidTokens?: number;
  rolloverTokens?: number;
  tokenRenewalDate?: string;
}

interface GraphQLResponse {
  data?: {
    user_details?: UserDetails[];
  };
}

// ── Fetch layer ───────────────────────────────────────────────

const GET_USER_DETAILS_QUERY = `
  query GetUserTokensFromSub($sub: String) {
    user_details(where: {cognitoId: {_eq: $sub}}) {
      id
      plan
      subscriptionGptTokens
      subscriptionModelTokens
      tokenRenewalDate
      streamTokens
      paidTokens
      subscriptionTokens
      rolloverTokens
    }
  }
`.trim();

/**
 * Fetch token balance via the Leonardo GraphQL API.
 *
 * @param idToken  - Auth0 access token captured by the MAIN-world content script.
 * @param userSub  - User's cognitoId (UUID; unchanged across the Auth0 migration).
 */
async function fetchUserDetails(idToken: string, userSub: string): Promise<UserDetails | null> {
  const res = await fetch(GRAPHQL_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${idToken}`,
      'content-type': 'application/json',
      'x-leo-schema-version': 'latest',
    },
    body: JSON.stringify({
      operationName: 'GetUserTokensFromSub',
      variables: { sub: userSub },
      query: GET_USER_DETAILS_QUERY,
    }),
  });

  if (res.status === 401 || res.status === 403) throw new AuthError(res.status);
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`leonardo graphql fetch failed: ${res.status}`);

  const body = (await res.json()) as GraphQLResponse;
  const details = body.data?.user_details?.[0] ?? null;
  console.log('[tokenomics] leonardo raw user_details:', details);
  return details;
}

// ── Official API-key endpoint (/me) ───────────────────────────

/** Subset of `user_details[0]` from GET /api/rest/v1/me. */
export interface MeUserDetails {
  subscriptionTokens?: number | null;
  paidTokens?: number | null;
  tokenRenewalDate?: string | null;
}

interface MeResponse {
  user_details?: MeUserDetails[];
}

/** Fetch the token balance with the user's own Leonardo API key. */
/** Renewal inputs: balance = subscriptionTokens, purchased = paidTokens (see renewal.ts). */
export type LeoPoll = RenewalPoll;

export async function fetchLeonardoUsageWithApiKey(apiKey: string): Promise<LeoPoll> {
  const res = await fetch(ME_URL, {
    headers: { Authorization: `Bearer ${apiKey}`, accept: 'application/json' },
  });

  if (res.status === 401 || res.status === 403) throw new AuthError(res.status, true);
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`leonardo /me fetch failed: ${res.status}`);

  const body = (await res.json()) as MeResponse;
  const d = body.user_details?.[0] ?? null;
  const now = Date.now();
  return {
    snapshot: mapMeToSnapshot(d, now),
    balance: num(d?.subscriptionTokens),
    purchased: num(d?.paidTokens),
    renewalKnown: isFutureDate(d?.tokenRenewalDate, now),
  };
}

/**
 * Pure mapper from /me `user_details[0]` to a snapshot. Exported for tests.
 * See the API KEY PATH note in the file header for why utilization is 0.
 */
export function mapMeToSnapshot(
  details: MeUserDetails | null,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  const totalLeft = num(details?.subscriptionTokens) + num(details?.paidTokens);
  const resetsAt = renewalDateToIso(details?.tokenRenewalDate ?? undefined, now);
  // No plan to tell daily (Free) from monthly (paid) allotments, so infer the
  // window from how far away the renewal is. Only affects the pace marker.
  const untilResetSec = (new Date(resetsAt).getTime() - now) / 1000;
  const windowDurationSec = untilResetSec > 36 * 3600 ? 30 * DAY_SEC : DAY_SEC;

  return {
    provider: 'leonardo',
    shortWindow: {
      label: 'Tokens',
      utilization: 0,
      resetsAt,
      windowDurationSec,
      sublabelOverride: `${totalLeft} tokens left`,
    },
    longWindow: null,
    extras: {},
    planLabel: 'Leonardo',
    capturedAt: now,
    estimated: false,
  };
}

// ── Public API ────────────────────────────────────────────────

/**
 * Fetch Leonardo token balance using an Auth0 Bearer token.
 *
 * @param idToken - The Auth0 access token captured by the MAIN-world leonardo-main content script.
 * @param userSub - The user's cognitoId (UUID) captured by the same content script.
 */
export async function fetchLeonardoUsage(
  idToken: string,
  userSub: string,
): Promise<LeoPoll> {
  const details = await fetchUserDetails(idToken, userSub);
  const now = Date.now();
  return {
    snapshot: mapToSnapshot(details, now),
    balance: num(details?.subscriptionTokens),
    purchased: num(details?.paidTokens),
    renewalKnown: isFutureDate(details?.tokenRenewalDate, now),
  };
}

/**
 * Pure mapper from UserDetails to a ProviderUsageSnapshot.
 * Exported for unit testing.
 *
 * @param details - The user_details object from the GraphQL response (may be null).
 * @param now     - Current time in milliseconds (injectable for tests).
 */
export function mapToSnapshot(
  details: UserDetails | null,
  now: number = Date.now(),
): ProviderUsageSnapshot {
  const subscriptionTokens = num(details?.subscriptionTokens);
  const paidTokens = num(details?.paidTokens);
  const rolloverTokens = num(details?.rolloverTokens);
  const totalLeft = subscriptionTokens + paidTokens + rolloverTokens;

  const cap = capForPlan(details?.plan);
  // When the cap is known, utilization = used/cap = (cap - remaining)/cap.
  // Unknown plan (cap 0) keeps the previous safe behavior of 0%.
  const utilization = cap > 0
    ? Math.min(100, Math.max(0, Math.round(((cap - totalLeft) / cap) * 100)))
    : 0;

  const shortWindow: WindowUsage = {
    label: 'Tokens',
    utilization,
    resetsAt: renewalDateToIso(details?.tokenRenewalDate, now),
    // Token allotments renew monthly (leonardo.ai/buy), including Free.
    windowDurationSec: 30 * DAY_SEC,
    sublabelOverride: `${totalLeft} tokens left`,
  };

  return {
    provider: 'leonardo',
    shortWindow,
    longWindow: null,
    extras: {},
    planLabel: planToLabel(details?.plan),
    capturedAt: now,
    estimated: false,
  };
}

// ── Helpers ───────────────────────────────────────────────────

/**
 * Convert `tokenRenewalDate` (ISO 8601 string from the API) to an ISO string
 * for resetsAt. Falls back to now + 24h when the field is absent or unparseable.
 */
function isFutureDate(date: string | null | undefined, now: number): boolean {
  if (typeof date !== 'string' || date.length === 0) return false;
  const ms = new Date(date).getTime();
  return Number.isFinite(ms) && ms > now;
}

function renewalDateToIso(renewalDate: string | undefined, now: number): string {
  if (typeof renewalDate === 'string' && renewalDate.length > 0) {
    const ms = new Date(renewalDate).getTime();
    if (Number.isFinite(ms) && ms > now) return new Date(ms).toISOString();
  }
  // No renewal date (seen live on a Free account via /me). Plans renew
  // monthly, but the day is unknown, so use now + 30d: the pace marker is
  // then 0 (hidden) and the popup shows "N tokens left" instead of a reset.
  return new Date(now + 30 * DAY_SEC * 1000).toISOString();
}

/**
 * Convert the plan string from the API to a user-facing plan label.
 * The API returns uppercase slugs (e.g. "FREE", "APPRENTICE_V2").
 */
function planToLabel(plan: string | undefined): string {
  if (!plan || typeof plan !== 'string' || plan.trim() === '') return 'Leonardo';
  const t = plan.trim().toUpperCase();
  switch (t) {
    case 'FREE':           return 'Free';
    case 'APPRENTICE':
    case 'APPRENTICE_V2': return 'Apprentice';
    case 'ARTISAN':
    case 'ARTISAN_V2':    return 'Artisan';
    case 'MAESTRO':
    case 'MAESTRO_V2':    return 'Maestro';
    default:
      // Capitalize first letter of first segment as a safe fallback.
      const first = t.split('_')[0] ?? t;
      return first.charAt(0) + first.slice(1).toLowerCase();
  }
}

/** Safely coerce an unknown value to a finite number; returns 0 otherwise. */
function num(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const parsed = parseFloat(v);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}
