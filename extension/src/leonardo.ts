/**
 * Leonardo.ai usage reader.
 *
 * Auth: AWS Cognito ID token (Bearer) + `x-leo-schema-version: latest` header.
 *
 * ── HOW THE TOKEN IS OBTAINED ────────────────────────────────────────────────
 * Leonardo uses AWS Cognito. On app.leonardo.ai the Amplify SDK stores the
 * current user's ID token in localStorage under the key:
 *   CognitoIdentityServiceProvider.<clientId>.<userSub>.idToken
 *
 * The `userSub` is the JWT `sub` claim (also stored under the LastAuthUser key).
 *
 * A dedicated ISOLATED-world content script (`content/leonardo-grab.ts`) reads
 * both the token and the userSub from localStorage and posts them to the service
 * worker via `{ kind: 'LEONARDO_TOKEN' }`. The SW caches them and passes them
 * here for the GraphQL call.
 *
 * ── API ───────────────────────────────────────────────────────────────────────
 * POST https://api.leonardo.ai/v1/graphql
 * Headers: Authorization: Bearer <idToken>, x-leo-schema-version: latest
 * Body: GetUserDetails GraphQL query (confirmed live 2026-06-01)
 *
 * ── RESPONSE SHAPE ───────────────────────────────────────────────────────────
 * Real response (Free plan, 2026-06-01):
 *   { "data": { "users": [ { "user_details": [
 *     { "plan": "FREE", "subscriptionTokens": 150, "paidTokens": 0,
 *       "rolloverTokens": 0, "tokenRenewalDate": "..." }
 *   ] } ] } }
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
    users?: Array<{
      user_details?: UserDetails[];
    }>;
  };
}

// ── Fetch layer ───────────────────────────────────────────────

const GET_USER_DETAILS_QUERY = `
  query GetUserDetails($userSub: String) {
    users(where: {user_details: {cognitoId: {_eq: $userSub}}}) {
      user_details {
        plan
        subscriptionTokens
        paidTokens
        rolloverTokens
        tokenRenewalDate
      }
    }
  }
`.trim();

/**
 * Fetch token balance via the Leonardo GraphQL API.
 *
 * @param idToken  - Cognito ID token from localStorage.
 * @param userSub  - Cognito user sub (JWT sub claim).
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
      operationName: 'GetUserDetails',
      variables: { userSub },
      query: GET_USER_DETAILS_QUERY,
    }),
  });

  if (res.status === 401 || res.status === 403) throw new AuthError(res.status);
  if (res.status === 429) throw new RateLimitError();
  if (!res.ok) throw new Error(`leonardo graphql fetch failed: ${res.status}`);

  const body = (await res.json()) as GraphQLResponse;
  const details = body.data?.users?.[0]?.user_details?.[0] ?? null;
  console.log('[tokenomics] leonardo raw user_details:', details);
  return details;
}

// ── Public API ────────────────────────────────────────────────

/**
 * Fetch Leonardo token balance using a Cognito Bearer token.
 *
 * @param idToken - The Cognito ID token from the leonardo-grab content script.
 * @param userSub - The Cognito user sub from the leonardo-grab content script.
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
