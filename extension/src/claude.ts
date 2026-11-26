import type { ProviderUsageSnapshot } from './snapshot';
import { clearCachedOrg, getCachedOrg, setCachedOrg } from './storage';
import type { CachedClaudeOrg } from './storage';
import { mapToSnapshot, pickChatOrg, planFromOrg } from './claude-map';
import type { UsageResponse } from './claude-map';

const API_BASE = 'https://claude.ai/api';

export class AuthError extends Error {
  constructor() {
    super('Not signed in to claude.ai');
    this.name = 'AuthError';
  }
}

export class RateLimitError extends Error {
  constructor() {
    super('claude.ai rate limited the request');
    this.name = 'RateLimitError';
  }
}

// ── Public API ──────────────────────────────────────────────

export async function fetchClaudeUsage(): Promise<ProviderUsageSnapshot> {
  const org = await getOrg();
  let usage: UsageResponse;
  try {
    usage = await fetchUsage(org.id);
  } catch (err) {
    // A cached org that now 403s may have been the wrong one; re-pick next poll.
    if (err instanceof AuthError) await clearCachedOrg();
    throw err;
  }
  return mapToSnapshot(usage, org.plan);
}

async function getOrg(): Promise<CachedClaudeOrg> {
  const cached = await getCachedOrg();
  if (cached) return cached;

  const res = await fetch(`${API_BASE}/organizations`, { credentials: 'include' });
  throwOnAuthOrRateLimit(res);
  if (!res.ok) throw new Error(`organizations fetch failed: ${res.status}`);

  const chatOrg = pickChatOrg(await res.json());
  // No chat-capable org means there is no claude.ai plan to read (API-only login).
  if (!chatOrg?.uuid) throw new AuthError();

  const org = { id: chatOrg.uuid, plan: planFromOrg(chatOrg) };
  await setCachedOrg(org);
  return org;
}

async function fetchUsage(orgId: string): Promise<UsageResponse> {
  const res = await fetch(`${API_BASE}/organizations/${orgId}/usage`, {
    credentials: 'include',
  });
  throwOnAuthOrRateLimit(res);
  if (!res.ok) throw new Error(`usage fetch failed: ${res.status}`);
  return (await res.json()) as UsageResponse;
}

function throwOnAuthOrRateLimit(res: Response): void {
  if (res.status === 401 || res.status === 403) throw new AuthError();
  if (res.status === 429) throw new RateLimitError();
}

