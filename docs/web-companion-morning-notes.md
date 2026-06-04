# Morning notes — pick up here

**Branch:** `feat/web-companion-chatgpt` (3 new commits since you went to sleep, not pushed)
**Built dist:** `~/projects/Tokenomics/extension/dist/` — already built, ready to load

## What landed overnight

Three commits on the branch, in order:

1. **`e689039` — ChatGPT local counter (Phase 1.5 pivot).** What we did together before you slept. The reader was changed from a polled endpoint to a content-script counter because `/wham/usage` is Codex-CLI-only — every shipping ChatGPT tracker uses the local-counter pattern.

2. **`aa027a9` — Midjourney reader + options page (Phase 4.5 + polish).** Done by two parallel developer agents while you slept:
   - **Midjourney** — `midjourney.ts` polls `www.midjourney.com/api/app/billing/balance` every 10 min. ⚠️ The endpoint shape is UNVERIFIED (Midjourney publishes no docs, no open-source tracker hits this endpoint). The parser maps the field names hypothesised in the plan doc and logs every raw response to the SW console. **First test of the morning: look for `[tokenomics] midjourney raw billing response:` in the SW console after signing in to midjourney.com/app, and compare the actual shape to what the parser expects.**
   - **Options page** — gear icon in the popup footer now opens a full browser tab with a ChatGPT plan override (Auto-detect / Free / Plus / Pro / Team). Auto-detect shows the currently-detected plan in parens. Mostly there for when `/backend-api/me` plan detection fails.
   - Also fixed: ChatGPT Pro quota was wrong (had 800/3h, actually uncapped per current OpenAI docs). Bumped sentinel to 5000/3h so Pro users see a tiny utilization bar.

3. **`1c72fdb` — Untrack Gemini research doc.** I'd accidentally committed it to the repo. Reverted; the file lives at `docs/web-companion-gemini-research.md` (untracked, private).

## What's ready to test in Chrome

Reload the extension at `chrome://extensions` (circular-arrow icon — don't remove and re-add, storage gets wiped). Then in order of confidence:

| Tab | Confidence | What to check |
|---|---|---|
| Claude | ✅ Known working | Same as yesterday — your live 5h + 7d utilization |
| OpenAI (ChatGPT) | 🟡 New, untested by you | Send a message on chatgpt.com → counter increments in popup. SW console should log `chatgpt plan auto-detected as 'free'` and `chatgpt message observed (model=gpt-5.x)` |
| Midjourney | ⚠️ Unverified endpoint shape | Sign in to midjourney.com/app → SW console logs raw response. If field names match, popup shows Fast Hours + GPU. If not, parser silently shows zeros and Rob needs to compare the raw log to the mapping in `extension/src/midjourney.ts:mapToSnapshot()` |
| Google AI | Empty state ("Track in Mac app") — Gemini deferred |
| GitHub Copilot / Cursor | Empty state — CLI providers, Mac app's job |

Also test the **options page**: click the gear icon in the popup footer. Should open a new tab. Select a non-Auto plan → confirm the popup's OpenAI tab shows the new plan label after the next message.

## Likely breakages I'd watch for

- **Midjourney endpoint shape wrong.** This is the most likely surprise. If the field names differ, fix is one function in `midjourney.ts`. The raw log line tells you exactly what to map.
- **`/backend-api/me` returns a shape we don't handle.** The plan extractor probes three paths (`account.plan`, `accounts.*.entitlement.plan_type`, top-level `plan`). If yours is somewhere else, plan auto-detect falls back to `unknown` (which the counter treats as Free). The options page is the workaround — just pick your real plan manually.
- **`/backend-api/conversation` request body lacks a `model` field.** Then the per-model breakdown (Thinking vs regular) won't work. Counter still works as a total. Look for `model=null` in the SW log.
- **Pre-existing ChatGPT messages from earlier today aren't counted.** Counter starts at zero on extension reload. That's a fundamental limitation of local counting.

## What I did NOT do (and why)

These need your hands because they touch the Mac app or external systems:

- **Phase 2 — Native Messaging Host bridge.** Requires new Swift `TokenomicsBridge` target in `project.yml`, signing/notarization changes, `WebCompanionService.swift` in the Mac app. Too far from a browser tab to verify safely.
- **Phase 5 — Safari target.** Mac app changes (Xcode target, App Group entitlement).
- **Phase 5.5 — Paired install flow.** Wires the dormant `MultiSelectStep` + `SetupPlanStep` into `ConnectorContainer`. Risky to do without you watching since the onboarding code is recently-stabilised.
- **Phase 6 — Publish.** Lawyer-gated, screenshots, store listings.
- **Phase 7 — Firefox.** Explicitly deferred per plan.
- **Phase 4 — Gemini.** You explicitly deferred this; I confirmed via research that nobody has a real endpoint and Google may ship one themselves soon. Details in `docs/web-companion-gemini-research.md`.

## Suggested order for the morning

1. Reload extension, verify Claude still works (regression check)
2. Send a ChatGPT message, verify the counter increments
3. Open the options page from the gear icon, try the plan selector
4. Sign in to midjourney.com/app, find the raw response in the SW console, **paste the JSON shape to me** — that's the one thing I can't verify without your account
5. If everything looks good, merge `feat/web-companion-chatgpt` → `main` and we move on

## Suggested next chunk after this lands

Pick one based on your appetite:
- **Phase 4.5 second pass** — once you've verified the MJ endpoint shape, lock the parser in and add Standard / Pro / Mega plan-tier handling if it's not already covered
- **Phase 2 NMH bridge** — wire the extension into the Mac app via Native Messaging. Big lift but the strategic unlock for the whole product (consumer providers showing in the menu bar too)
- **Polish** — Claude plan detection (currently hardcoded "Pro"), proper "Reset counter" button on the OpenAI tab, per-model breakdowns
- **Phase 4 Gemini revisit** — if you decide the local-counter UX feels OK after living with ChatGPT, do Gemini the same way
