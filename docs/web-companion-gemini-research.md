# Web Companion — Gemini consumer reader research

> **⚠️ UPDATE 2026-06-01 — THE DEFERRAL CONDITION HAS FIRED.**
> This doc recommended waiting for Google to ship its own usage dashboard before building a Gemini
> reader. **Google shipped it: `gemini.google.com/usage` went live ~May 17, 2026** (compute-based
> limits; adjusted May 28) showing real usage %, a 5-hour reset countdown, and a weekly tracker.
> That means Gemini can now be a **real-data reader (`estimated: false`), like Claude — not the
> estimated local counter this doc analyzed.** The trust objection is gone. Everything below the line
> is preserved as the original May 2026 analysis (now largely historical). **The build-ready plan is
> `docs/gemini-reader-spec.md`.** Next step: capture the live `/usage` network response.
> Sources: 9to5Google "Gemini new usage limits" (2026-05-28); AndroidSage (2026-05-19).

---

**Status:** Research only — Rob explicitly deferred building this in Phase 1.5. Document captures what's true as of May 2026 so the next conversation can pick up cleanly.

**Why this exists:** Phase 1.5 confirmed that ChatGPT consumer has no usable server-side usage endpoint either (Codex CLI's `/wham/usage` is bearer-token only). The pivot to a local-counter approach for ChatGPT is now the same UX call we wanted to defer for Gemini. This doc captures the latest on Gemini so we can decide together when to revisit.

---

## State of the world (May 2026)

### Google is actively building this themselves

Per APK teardown coverage (Android Authority, April 2026), Google is developing an in-app Gemini usage dashboard that will display:
- Percentage of current quota used
- Reset time
- Last update timestamp

Position: "near the account switcher" in the Google app.

**Caveat:** APK teardowns surface work-in-progress code. May not ship publicly. No timeline given.

**Strategic implication:** If Google ships this, there will likely be a public-ish endpoint the web app calls to populate it. We'd switch from "estimated local counter" to "real numbers" the day that lands. Worth waiting for IF the timeline is short.

Source: [Google Gemini usage limit tracker leak (Android Authority)](https://www.androidauthority.com/google-gemini-usage-limit-tracker-apk-teardown-3661411/)

### What existing trackers actually do

Reviewed every visible Gemini consumer tracker. Findings:

| Project | Approach for Gemini consumer | Notes |
|---|---|---|
| **`argmin-com/extension`** | Local counter — content script on `gemini.google.com`, observes outbound `batchexecute` requests, counts locally per model | The most ambitious multi-provider tracker. Same pattern as us for ChatGPT. |
| `gov-00/gemini-tracker` | API rate limits only | Targets `ai.google.dev` API key users, not the consumer web app. Not applicable. |
| `Beaulewis1977/gemini-context-extension` | Context window tracker | For the Gemini CLI, not the web app. Not applicable. |

**Conclusion:** Nobody has a working real-data tracker for Gemini consumer. The most ambitious competitor uses the same local-counter pattern we just built for ChatGPT.

### The endpoint that doesn't exist (yet)

Gemini's web app posts to `https://gemini.google.com/_/BardChatUiServer/data/batchexecute?...` for each chat turn. Response is the `[[1, ...]]`-style packed array format Google uses across Bard/Gemini. The payload doesn't carry a clean utilization field — there's nothing to parse for "you've used 7 of 10 Pro messages today." We'd have to count outbound POSTs ourselves.

### Free plan quotas (as of May 2026)

Published Google docs are stable on:
- Gemini (free): ~10 Pro 1.5 messages / day, then falls back to Flash
- Gemini AI Pro ($20/mo): ~100 Pro 2.5 / day, generous Flash
- Gemini AI Ultra ($250/mo): ~500 Pro 2.5 / day, near-unlimited Flash

These shift quarterly. We should not hardcode without a monthly verification routine (similar to the OAuth monitor we already have for OpenAI/Google consumer-OAuth changes).

---

## What "ship Gemini" would look like (if Rob says yes later)

Mechanically identical to the ChatGPT pivot already in `feat/web-companion-chatgpt`:

1. New `extension/src/gemini.ts` — quota table per plan, `deriveSnapshot()` from a counter log. Plan auto-detection via... probably no easy endpoint, so manual selector in the options page.
2. New `extension/src/content/gemini-watch.ts` — content script on `gemini.google.com/*`, MAIN-world fetch patch observing POSTs to `/_/BardChatUiServer/data/batchexecute`. Per call, extract the model from the request (URL params? hash? — need to verify) and post `GEMINI_MESSAGE` to SW.
3. Storage keys: `geminiSnapshot`, `geminiEvents`, `geminiPlanOverride`.
4. Manifest: add `https://gemini.google.com/*` to host_permissions, content_scripts entry.
5. Popup: add `'gemini'` to `VISIBLE_PROVIDERS`. EmptyState already has a `gemini` tab — change the "Track in menu bar app" copy to "Open gemini.google.com and chat" similar to ChatGPT's pattern.
6. Options page: add a Gemini section with plan selector (Auto-detect is likely useless here; default to manual).
7. `(estimated)` indicator in Header (already wired — same flag as ChatGPT).

Estimated build cost: ~1-2 hours of Claude time. Lower than ChatGPT because we now have the local-counter pattern down.

---

## Recommendation for the next conversation

Two reasonable paths:

**A. Wait for Google's official dashboard.** Don't ship the estimated path. The APK teardown suggests Google's own UI is coming. When it ships, take a couple of hours to find the endpoint and ship a real reader. This preserves the "every Tokenomics number is real" principle for Gemini specifically.

**B. Ship the estimated counter now, replace when Google ships theirs.** Same UX as ChatGPT today. Two `(estimated)` providers in the popup (ChatGPT + Gemini) until Google's endpoint lands.

If Rob's instinct on "estimated everywhere undermines trust" is firm, lean A. If he wants closed-loop coverage of all the major consumer assistants, lean B.

Either way: **do not ship Gemini estimated without explicitly re-asking** — Rob's deferral is on the record and shouldn't be overridden by an autonomous session.

---

## Sources

- [Google Gemini usage limit tracker leak (Android Authority, April 2026)](https://www.androidauthority.com/google-gemini-usage-limit-tracker-apk-teardown-3661411/)
- [Google Gemini may get usage dashboard (Android Headlines, April 2026)](https://www.androidheadlines.com/2026/04/google-gemini-usage-limit-dashboard-leaks.html)
- [`argmin-com/extension`](https://github.com/argmin-com/extension) — multi-platform AI tracker, source of "local counter" pattern for Gemini
- [`gov-00/gemini-tracker`](https://github.com/gov-00/gemini-tracker) — API key tracker (not consumer)
- [Gemini API rate limits docs (Google)](https://ai.google.dev/gemini-api/docs/rate-limits) — for context on the API tier, not consumer
