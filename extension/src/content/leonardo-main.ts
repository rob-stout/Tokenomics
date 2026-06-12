/**
 * MAIN-world content script for Leonardo.ai Auth0 token interception.
 *
 * Declared in manifest.json with `"world": "MAIN"` so it runs directly in the
 * page's JavaScript context — no chrome.* / browser.* APIs are available here.
 *
 * WHY MAIN WORLD:
 * After Leonardo migrated from AWS Cognito to Auth0, the access token is no
 * longer stored in localStorage. Auth0 keeps it purely in page memory (a
 * closure inside the SDK). The only reliable way to capture it is to observe
 * it off the page's own outgoing requests to api.leonardo.ai/v1/graphql — which
 * requires a fetch hook running inside the page's JS context (MAIN world).
 *
 * This script wraps window.fetch as a TRANSPARENT PASS-THROUGH OBSERVER:
 *   - The original fetch is always called and its result / error is returned
 *     to the page untouched.
 *   - ALL extension logic is inside try/catch and must NEVER alter, block,
 *     delay, or surface anything to the page's requests.
 *
 * When both idToken and userSub are captured (and at least one changed since
 * last post), results are forwarded to leonardo-watch.ts via window.postMessage.
 * The service worker does the periodic polling — no timer loop is needed here.
 *
 * This script MUST NOT use any chrome.* / browser.* APIs.
 * Results are posted to leonardo-watch.ts (the ISOLATED relay) via
 * window.postMessage({ tag: LEO_TAG, kind: 'LEONARDO_TOKEN', ... }, '*').
 */

// Make this file a TypeScript module so top-level const declarations don't
// collide with other MAIN-world scripts (gemini-main.ts) in tsc's global scope.
export {};

// --- constants shared with leonardo-watch.ts (must match exactly) ---
const LEO_TAG = '__tokenomics_leonardo_msg__';

// --- idempotency guard (soft-nav / multiple-injection protection) ---
const GUARD_KEY = '__tokenomics_leonardo_active__';
const w = window as unknown as Record<string, unknown>;
if (!w[GUARD_KEY]) {
  w[GUARD_KEY] = true;

  // ── Module-level token cache ──────────────────────────────────────────────
  // Both values start empty; we only post when we have both and at least one
  // has changed since the last post.
  let cachedIdToken = '';
  let cachedUserSub = '';
  let lastPostedIdToken = '';
  let lastPostedUserSub = '';

  // ── Header extraction helpers ─────────────────────────────────────────────

  /**
   * Extract the raw Authorization header value from the fetch arguments,
   * handling all three forms `init.headers` can take: Headers object,
   * plain record, or array of [key, value] pairs. Also handles the case
   * where `input` is a Request object with its own headers.
   */
  function extractAuthHeader(
    input: RequestInfo | URL,
    init: RequestInit | undefined,
  ): string | null {
    // Prefer init.headers over Request.headers (init takes precedence per spec).
    if (init?.headers) {
      const h = init.headers;
      if (h instanceof Headers) {
        return h.get('authorization');
      }
      if (Array.isArray(h)) {
        // Array of [key, value] pairs.
        for (const pair of h as [string, string][]) {
          if (typeof pair[0] === 'string' && pair[0].toLowerCase() === 'authorization') {
            return pair[1] ?? null;
          }
        }
        return null;
      }
      // Plain object / HeadersInit record.
      const record = h as Record<string, string>;
      for (const key of Object.keys(record)) {
        if (key.toLowerCase() === 'authorization') return record[key] ?? null;
      }
      return null;
    }

    // Fall back to Request.headers when input is a Request.
    if (input instanceof Request) {
      return input.headers.get('authorization');
    }

    return null;
  }

  /**
   * Strip a leading "Bearer " prefix (case-insensitive) from an auth header
   * value and return the bare token. Returns empty string for empty/null input.
   */
  function stripBearer(raw: string | null): string {
    if (!raw) return '';
    return raw.replace(/^bearer\s+/i, '').trim();
  }

  // ── Body parsing helpers ──────────────────────────────────────────────────

  /**
   * Attempt to extract `userSub` from the GraphQL request body.
   *
   * Target: operationName === 'GetUserTokensFromSub' OR variables.sub exists
   * OR a `cognitoId: { _eq: <uuid> }` filter in the variables.
   *
   * Returns empty string when nothing useful is found.
   */
  function extractUserSubFromBody(bodyStr: string): string {
    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(bodyStr) as Record<string, unknown>;
    } catch {
      return '';
    }

    // Primary path: variables.sub (confirmed live shape)
    const variables = parsed.variables as Record<string, unknown> | undefined;
    if (typeof variables?.sub === 'string' && variables.sub.length > 0) {
      return variables.sub;
    }

    // Secondary path: operationName match — sub may be under a different key;
    // scan the variables object for anything that looks like a UUID.
    if (parsed.operationName === 'GetUserTokensFromSub' && variables) {
      for (const val of Object.values(variables)) {
        if (typeof val === 'string' && isUuid(val)) return val;
      }
    }

    // Tertiary path: cognitoId._eq filter somewhere in variables
    const sub = findCognitoId(variables);
    if (sub) return sub;

    return '';
  }

  /** Returns true if the string looks like a UUID (any version). */
  function isUuid(s: string): boolean {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
  }

  /**
   * Recursively walk an object looking for { cognitoId: { _eq: value } }
   * and return `value` when found.
   */
  function findCognitoId(obj: unknown): string | null {
    if (!obj || typeof obj !== 'object') return null;
    const record = obj as Record<string, unknown>;
    if ('cognitoId' in record) {
      const ci = record.cognitoId as Record<string, unknown> | undefined;
      if (typeof ci?._eq === 'string' && ci._eq.length > 0) return ci._eq;
    }
    for (const val of Object.values(record)) {
      const found = findCognitoId(val);
      if (found) return found;
    }
    return null;
  }

  // ── Posting helper ────────────────────────────────────────────────────────

  function maybePost(): void {
    if (!cachedIdToken || !cachedUserSub) return;
    if (cachedIdToken === lastPostedIdToken && cachedUserSub === lastPostedUserSub) return;
    lastPostedIdToken = cachedIdToken;
    lastPostedUserSub = cachedUserSub;
    window.postMessage(
      { tag: LEO_TAG, kind: 'LEONARDO_TOKEN', idToken: cachedIdToken, userSub: cachedUserSub },
      '*',
    );
  }

  // ── fetch hook ────────────────────────────────────────────────────────────

  const _originalFetch = window.fetch.bind(window);

  window.fetch = function patchedFetch(
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> {
    // Always fire the real fetch first, unconditionally.
    const resultPromise = _originalFetch(input, init);

    // Determine whether this is a Leonardo GraphQL call.
    const url =
      input instanceof Request ? input.url : typeof input === 'string' ? input : String(input);

    if (url.includes('api.leonardo.ai/v1/graphql')) {
      // Observe — never await the result promise for our logic, never throw.
      try {
        // --- extract Authorization header ---
        const rawAuth = extractAuthHeader(input, init);
        const token = stripBearer(rawAuth);
        if (token.length > 0) cachedIdToken = token;

        // --- extract userSub from body ---
        // `init.body` is a string for JSON payloads; otherwise clone a Request.
        const bodyStr: string | null =
          typeof init?.body === 'string'
            ? init.body
            : input instanceof Request
              ? null // handle via async path below
              : null;

        if (bodyStr !== null) {
          const sub = extractUserSubFromBody(bodyStr);
          if (sub.length > 0) cachedUserSub = sub;
          maybePost();
        } else if (input instanceof Request) {
          // Clone the Request to read its body without consuming the original.
          try {
            input
              .clone()
              .text()
              .then((text) => {
                try {
                  const sub = extractUserSubFromBody(text);
                  if (sub.length > 0) cachedUserSub = sub;
                  maybePost();
                } catch {
                  // ignore
                }
              })
              .catch(() => {
                // ignore — body may be non-text or already consumed
              });
          } catch {
            // clone() can throw on a disturbed body — ignore
          }
        }
      } catch {
        // NEVER surface extension errors to the page.
      }
    }

    return resultPromise;
  };
  // The hook lives for the page's lifetime — no cleanup needed.
}
