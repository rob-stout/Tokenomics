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
 * No total is available from this endpoint — utilization is left at 0.
 * // TODO: plan→cap table for a real ring — e.g. Free=150, Apprentice=8500, etc.
 *
 * NOTE: `apiCredit` / `apiSubscriptionTokens` fields are a SEPARATE developer-API
 * pool and are intentionally excluded from this reader.
 */

import type { ProviderUsageSnapshot, WindowUsage } from './snapshot';

const GRAPHQL_URL = 'https://api.leonardo.ai/v1/graphql';
const DAY_SEC = 86400;

export class AuthError extends Error {
  constructor(status: number) {
    super(`Not signed in to leonardo.ai (status ${status})`);
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
): Promise<ProviderUsageSnapshot> {
  const details = await fetchUserDetails(idToken, userSub);
  return mapToSnapshot(details, Date.now());
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

  // No total cap available from this endpoint — utilization unknown.
  // TODO: plan→cap table for a real ring — Free=150, Apprentice=8500, Artisan=25000, etc.
  const shortWindow: WindowUsage = {
    label: 'Tokens',
    utilization: 0,
    resetsAt: renewalDateToIso(details?.tokenRenewalDate, now),
    windowDurationSec: DAY_SEC,
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
function renewalDateToIso(renewalDate: string | undefined, now: number): string {
  if (typeof renewalDate === 'string' && renewalDate.length > 0) {
    const ms = new Date(renewalDate).getTime();
    if (Number.isFinite(ms) && ms > now) return new Date(ms).toISOString();
  }
  return new Date(now + DAY_SEC * 1000).toISOString();
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
