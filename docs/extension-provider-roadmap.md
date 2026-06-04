# Extension Provider Roadmap — Post Beta-3

*Written 2026-06-02. Covers which AI tools to add as browser-extension usage readers after the beta-3 release.*

---

## Thesis

The extension's value proposition is simple: one place to see how close you are to a hard limit, in real numbers. That constraint eliminates most candidates before you write a line of code. A reader is only worth the maintenance burden if three conditions all hold: (1) there is a real, recurring consumer quota users actively hit and complain about, (2) you can read the number honestly from the web session — ideally a clean JSON endpoint, not a fragile DOM scrape — and (3) the user is in the same audience as everyone already using Tokenomics (AI coders and AI-forward creatives, not Office workers). Most of the 20 tools evaluated fail at least one bar. The realistic post-beta-3 list is four to six additions, not twenty.

The real constraint is not build time (Claude Code handles that in hours) — it is Rob's testing time and the ongoing maintenance tax of parsers that rot when the provider changes their UI or endpoint. Every web reader you ship is a monitoring obligation. Default to fewer, higher-confidence additions.

---

## Kill List

These are eliminated. One line each.

| Tool | Reason |
|---|---|
| **Microsoft Copilot** | Text chat is effectively unlimited; no honest consumer quota to track; image boost limit is a toast-only DOM signal; 60 AI credits meter Office actions, not chat. |
| **Mistral Le Chat** | Vague "fair use" soft cap with no published number and no usage endpoint or counter in the web app — only a reactive "limit reached" error. |
| **DeepSeek** | Free, no consumer cap at all; only metering is dollar-billed developer API. |
| **Sora** | Consumer app shut down April 26, 2026; API sunsets September 24, 2026. Building a reader for a dead product. |
| **v0 (Vercel)** | Dollar-denominated prepaid credit balance, not a recurring quota window — exactly the "bills in dollars" shape the brief excludes. |
| **Replit** | Dollar credit pool that flips to pay-as-you-go; effort-based variable cost per checkpoint means no stable integer to display. |
| **Pika** | No confirmed honest read path; official API is third-party Fal generation (API-key only); ToS explicitly prohibits crawlers. |
| **Luma (Dream Machine)** | Only confirmed clean JSON endpoint is the dollar-billed developer API — not the consumer web session; no verified read path for consumer balance. |
| **Windsurf** | Honest usage signal lives in the editor sidebar, not the browser; web presence is a Stripe billing portal; only documented usage API is Enterprise-gated with service keys. |

Nine tools, gone. That leaves eleven to evaluate seriously.

---

## Tier 1 — Build Next

These clear all three bars. Real endpoint, real consumer limit, right audience. Build them in the order listed.

### 1. Grok (grok.com)
| Attribute | Value |
|---|---|
| Metering model | Per-window query quota: remainingQueries / totalQueries within a rolling ~2h window. requestKind splits: DEFAULT, REASONING, DEEPSEARCH. Free ~20-30/window; SuperGrok and Heavy raise the ceiling but still throttle. |
| Readability | Real endpoint — POST `grok.com/rest/rate-limits` with `{requestKind, modelName}`, returns clean JSON. Cookie/SSO auth only, no API key. |
| Effort | Low — endpoint is already reverse-engineered and consumed by multiple shipping tools (a Chrome extension, a Tampermonkey script, a Python wrapper). The build is essentially wiring the existing Claude/Midjourney fetch pattern to a known-good URL. |
| Maintenance risk | Medium — xAI actively re-tunes limits and has changed the endpoint before; the reader must fail gracefully. Query DEFAULT kind as the primary signal; present it as "X of Y remaining this window" not "X per day" (the window is rolling). |
| Audience | High — Grok Free users hit the 2h wall constantly; even paid SuperGrok users encountered throttling in May 2026. Squarely overlaps with the AI-coder audience already using Claude/ChatGPT. |
| Note | New brand. Not a pool of an existing brand. |

### 2. ElevenLabs
| Attribute | Value |
|---|---|
| Metering model | Monthly character credit allowance. Free 10K, Starter 30K, Creator 121K, Pro 600K. Maps ~1:1 to characters on Multilingual v2. Hard cap; resets monthly; rollover up to 2 months. |
| Readability | Real endpoint — `GET /v1/user/subscription` returns `character_count` + `character_limit` + `next_character_count_reset_unix` as clean JSON. **One open item before building:** the documented endpoint authenticates via `xi-api-key` header; confirm the logged-in dashboard calls a session-cookie-authed variant by capturing one live DevTools session. If the dashboard SPA calls the same endpoint with a session cookie, this is a 30-minute build. If it's API-key only, it drops to skip. |
| Effort | Low (pending the DevTools confirmation above — single session capture). |
| Maintenance risk | Low — ElevenLabs has a stable documented REST endpoint; the field names are published and unlikely to change without notice. |
| Audience | High — ElevenLabs is the default voice AI tool for indie developers and content creators, the exact creative half of the Tokenomics audience. Free tier users hit 10K characters in a single podcast script. |
| Note | New brand. Not a pool of an existing brand. |

### 3. Perplexity
| Attribute | Value |
|---|---|
| Metering model | Perplexity Pro ($20/mo) enforces per-feature quotas users actively hit: Pro Searches (~100-200/day or per week depending on account), Deep Research (~20/day), Labs (~25/day). Period enforcement has been shifting (daily to weekly) throughout 2026. |
| Readability | Real endpoint — `GET https://www.perplexity.ai/rest/rate-limit/all` returns live per-feature quota/remaining data as clean JSON. Cookie-gated (403 unauthenticated). Same web-session pattern as Claude and Midjourney. |
| Effort | Low — clean REST JSON, familiar auth pattern. |
| Maintenance risk | Medium — endpoint is undocumented and internal; Perplexity has been volatilely changing both the limit values and the enforcement period throughout 2026, triggering public user complaints. The display must surface multiple feature quotas (Pro Searches, Deep Research, Labs) and handle per-account promo variations gracefully rather than collapsing to a single ring. |
| Audience | Medium — Perplexity Pro users overlap more with the "power researcher" profile than pure AI coders, but there is meaningful overlap with the Tokenomics user base. The real signal here is that Perplexity users complain loudly about hitting limits, which means they want to see the numbers. |
| Note | New brand. Multi-feature quota display (3 windows) makes this slightly more complex than a single-ring provider — consider showing Pro Searches as the primary ring with Deep Research / Labs as secondary bars. |

### 4. Leonardo.ai
| Attribute | Value |
|---|---|
| Metering model | Monthly token allowance. Free 150 tokens/day (24h reset, ~10 images); paid tiers 8,500–60,000/month. Web balance = subscriptionTokens + paidTokens, distinct from the API billing pool. |
| Readability | Real endpoint — web app uses a Hasura GraphQL backend at `api.leonardo.ai/v1/graphql`; the `users` record exposes `subscriptionTokens` + `paidTokens` as clean JSON, readable from the web session bearer token. |
| Effort | Medium — GraphQL query construction rather than a plain REST GET; need to capture the exact query shape from a live session; also need to reconcile the two token pools (subscription + paid) into a single ring. |
| Maintenance risk | Medium — session bearer token capture, not a cookie like Midjourney. GraphQL schema could change. But the data source is honest and the field names are stable. |
| Audience | High — image generation tool with a strong indie developer / creative following; fits the same creative half of the audience as Midjourney. Free daily cap (150 tokens) means free users hit it constantly. |
| Note | New brand. Adds a second image generation reader alongside Midjourney. |

---

## Tier 2 — Worth It Later

These clear the core bars but require a live-session endpoint confirmation before committing to build. Do the DevTools spike first; then promote to Tier 1 or drop.

### Cursor (web dashboard)
| Attribute | Value |
|---|---|
| Metering model | Dollar-denominated included-usage budget (~$20/month Pro). Dashboard shows USD used vs limit and included-usage percentage. Legacy accounts still show request counts (e.g., 120 of 500). |
| Readability | Real endpoint — `POST cursor.com/api/dashboard/get-current-period-usage` returns clean JSON with USD used, limit, API/Auto split, percentages, cycle end. Auth via `WorkosCursorSessionToken` cookie. Legacy GET endpoint also exists. |
| Effort | Medium — two account models (dollar vs request count) require branching; dollar framing is less intuitive than a request count for a ring display; must reconcile with the existing local `state.vscdb` Cursor reader already in the Mac app. |
| Maintenance risk | Medium — unofficial endpoints with known intermittent 400s; two account models add fragility. |
| Audience | High — Cursor Pro users are core Tokenomics audience. |
| Key decision | The Mac app already reads Cursor locally from `state.vscdb`. Before building the web reader, decide whether the extension's web-session read REPLACES the local Mac reader or AUGMENTS it (two Cursor pools: local tab usage vs web billing). Conflating them would be confusing; the web reader is arguably more authoritative (real billing vs. local state). Resolve this before building. |
| Note | Not a new brand — Cursor is already in the Mac app. This is a new data source for an existing brand. |

### Suno
| Attribute | Value |
|---|---|
| Metering model | Monthly credit allowance. Free 50/day (~10 songs); Pro 2,500/mo; Premier 10,000/mo. Credits reset monthly. |
| Readability | Real endpoint — `GET https://studio-api.prod.suno.com/api/billing/info/` returns `total_credits_left`, `monthly_limit`, `monthly_usage`, `period` as clean JSON. Auth via Clerk session JWT (`__session` cookie). Community wrappers already confirmed this. |
| Effort | Low. |
| Maintenance risk | Medium — undocumented internal endpoint; Clerk JWT session vs cookie is a slightly different auth pattern than existing readers. |
| Audience | Medium — audio/music tool, strongest for the creative half of the base; AI coders less likely to have Suno accounts. Lower priority than Grok/ElevenLabs/Perplexity for the coding audience. |
| Note | New brand. MEMORY.md notes Suno is already "Coming Soon" in the Mac app enum — confirm the extension reader and Mac app pool are properly coordinated before shipping. |

### Suno is already in the Coming Soon enum, and so is Udio:

### Udio
| Attribute | Value |
|---|---|
| Metering model | Monthly credit quota. Free 10/day + 100/month; Standard 2,400/mo; Pro 6,000/mo. No rollover. |
| Readability | Probable real endpoint — web app shows live credit balance, implying a session-authed JSON call; a community Chrome extension already reads per-track credit cost. Exact endpoint path unconfirmed — needs a one-time live DevTools capture. |
| Effort | Medium (endpoint confirmation step required). |
| Maintenance risk | Medium — undocumented, must be reverse-engineered. |
| Audience | Medium — creative only; pairs with Suno as a second audio reader if you want the music-creator segment. |
| Note | Also already in the Mac app Coming Soon enum (same coordination note as Suno). Only build if Suno lands first and the audience response is positive — don't build both simultaneously. |

### Ideogram
| Attribute | Value |
|---|---|
| Metering model | Monthly priority-credit pool. Free ~10 slow credits/week; Basic 400/mo; Plus 1,000/mo; Pro 3,000+/mo. When priority credits exhaust, paid users drop to slow queue (unlimited but multi-minute waits). |
| Readability | Probable real endpoint — web app surfaces "remaining priority credits" in the User Menu, fetched client-side; architecture mirrors the Midjourney reader. Exact endpoint unconfirmed — needs live DevTools capture. |
| Effort | Medium (endpoint confirmation step required). |
| Maintenance risk | Medium. |
| Audience | High — image generation, strong creative overlap. Ideogram is smaller than Midjourney and Leonardo but growing. |
| Note | New brand. Only build after Leonardo.ai is live — they serve the same audience and you want to validate image-gen reader demand before building a second one. |

### Bolt (bolt.new)
| Attribute | Value |
|---|---|
| Metering model | Free 1M tokens/month with a 300K/day hard cap; Pro ~10M/month. Daily cap pauses AI generation completely. |
| Readability | Probable real endpoint — "Subscription & Tokens" settings page almost certainly calls an undocumented StackBlitz XHR. **Must do a DevTools spike first** — the opt-in in-chat counter cannot be relied on; the settings-page XHR is the target. If it is clean JSON, this is a build. If it is DOM-only, skip. |
| Effort | Medium (pending endpoint confirmation). |
| Maintenance risk | Medium — undocumented endpoint; StackBlitz ships frequently. |
| Audience | High — prompt-to-app AI coding tool; squarely the Tokenomics coder audience. Free daily cap (300K) is painful and well-known. |
| Note | New brand. High audience fit makes the DevTools spike worth doing. |

### Lovable
| Attribute | Value |
|---|---|
| Metering model | Credit-based. Free 5/day, 30/month. Pro 100/month + 5/day. Credits scale with action complexity. |
| Readability | Probable real endpoint — credit bar in the UI implies an internal XHR; unconfirmed. Needs live DevTools capture before committing. |
| Effort | Medium (pending endpoint confirmation). |
| Maintenance risk | High — no documented or confirmed endpoint; if DOM-only, maintenance risk is high enough to skip. |
| Audience | High — flagship vibe-coding tool, overlaps directly with the Tokenomics AI-coder audience. Free daily cap (5 credits) is extremely tight and a constant friction point. |
| Note | New brand. The tight free limit creates strong motivation to track this. Only build if the DevTools spike surfaces clean JSON — do not build a DOM scraper for Lovable. |

### Runway
| Attribute | Value |
|---|---|
| Metering model | Monthly credit allowance. Standard 625/mo; Pro 2,250/mo; Unlimited (Max) 2,250 + uncapped Relaxed. Credits reset monthly with no rollover. |
| Readability | Probable real endpoint — `app.runwayml.com` almost certainly fetches balance via an internal undocumented XHR. Unconfirmed without DevTools. |
| Effort | Medium. |
| Maintenance risk | High — SPA that ships frequently; active pricing overhaul (Unlimited → Max migration June/September 2026); semantics of credits are changing mid-cycle. |
| Audience | Medium — video generation, creative-only. Overlaps with Midjourney audience but is a different workflow. |
| Note | New brand. The active pricing overhaul is a red flag — wait until the Unlimited → Max migration completes (September 2026) before building, or the credit semantics you ship will immediately be wrong. |

### Poe (Quora)
| Attribute | Value |
|---|---|
| Metering model | Compute points per subscription tier ($4.99 to $249.99/mo). Daily or monthly caps depending on tier. One balance across all models (Claude/GPT/Gemini through Poe). |
| Readability | The only web-session read is an undocumented internal GraphQL call gated by a rotating `poe-formkey` CSRF header — the same fragility as Gemini's batchexecute but without the confirmed payload shape. The clean REST balance endpoint (`api.poe.com/usage`) is API-key only. |
| Effort | High. |
| Maintenance risk | High. |
| Audience | High — Poe is an interesting case because one subscription covers Claude/GPT/Gemini, making the balance distinctly valuable to track. |
| Note | The CSRF-gated GraphQL path is the same fragility class as the current Gemini batchexecute reader, but without a confirmed payload. Only worth attempting if a live DevTools session confirms a stable-looking response shape. |

### Kling
| Attribute | Value |
|---|---|
| Metering model | Daily free credits (~66/day) plus monthly paid pools. Video generation burns credits fast. |
| Readability | Session endpoint likely exists (sidebar balance), but `app.klingai.com` is behind Cloudflare/Akamai bot protection (HTTP 446 on programmatic fetch). This is a meaningful technical barrier — the extension's fetch from the service worker is not a browser tab and may be blocked. |
| Effort | Medium to high (bot protection uncertainty). |
| Maintenance risk | High — Cloudflare-protected; audience is creative/video only; multi-bucket credit model (subscription + 2-year top-up + refunded credits) complicates honest display. |
| Audience | Medium — video generation, creative-only. |
| Note | The bot protection issue is a hard technical unknown. If `app.klingai.com` blocks fetch from a service worker context, there is no path forward without a content script injection. Spike this before committing. |

---

## Priority Ranking: Kept Candidates

Ranked by (audience fit × limit pain) / (effort + maintenance). Values are relative, 1–5 scale. User-base column added June 2026 — see sizing section below for methodology.

| Provider | Audience Fit | Limit Pain | Effort | Maintenance | Score | Tier | ~Consumer User Base |
|---|---|---|---|---|---|---|---|
| **Grok** | 5 | 5 | 1 | 2 | 8.3 | 1 | ~60M MAU (overwhelmingly consumer; <1% enterprise penetration as of mid-2025) |
| **ElevenLabs** | 5 | 4 | 1 | 1 | 10.0 | 1 | ~1M+ registered; ~558K mobile MAU; $330M ARR (mostly consumer + indie devs) |
| **Perplexity** | 4 | 5 | 1 | 3 | 5.0 | 1 | ~45M MAU on core search; 100M+ across all products; 57% aged 18–34 (consumer-heavy) |
| **Leonardo.ai** | 5 | 4 | 2 | 2 | 5.0 | 1 | ~19M registered; ~1.2M MAU; 65%+ professional artists/creatives |
| **Bolt** | 5 | 5 | 2 | 2 | 6.25 | 2 | Not publicly reported |
| **Lovable** | 5 | 5 | 2 | 4 | 4.2 | 2 | Not publicly reported |
| **Cursor (web)** | 5 | 4 | 2 | 3 | 3.8 | 2 | Not publicly reported |
| **Suno** | 3 | 4 | 1 | 3 | 3.5 | 2 | Not publicly reported |
| **Ideogram** | 5 | 3 | 2 | 3 | 3.0 | 2 | Not publicly reported |
| **Poe** | 5 | 4 | 5 | 5 | 1.8 | 2 | Not publicly reported |
| **Udio** | 3 | 4 | 2 | 3 | 2.8 | 2 | Not publicly reported |
| **Runway** | 3 | 4 | 2 | 5 | 2.0 | 2 | Not publicly reported |
| **Kling** | 3 | 4 | 4 | 5 | 1.6 | 2 | Not publicly reported |

---

## Player Sizing: Big Three vs Candidates

Added June 2026. The purpose of this table is calibration: how large are the platforms Tokenomics already supports, and how do the new candidates compare? This matters because audience size is a rough proxy for new-user acquisition ceiling if Tokenomics gets word-of-mouth spread within a tool's user base.

Sources: DemandSage, fatjoe, getpanto.ai, ppc.land (all accessed June 2026). All figures are estimates synthesized from third-party analytics — no platform publishes a single audited MAU. Flag: Claude's consumer MAU figure is notably hard to pin down because Anthropic does not publish it; the ~30M estimate is synthesized from web traffic and third-party app analytics.

### The Platforms Tokenomics Already Supports

| Platform | ~Consumer MAU | Scale context | Notes |
|---|---|---|---|
| **ChatGPT (OpenAI)** | ~1 billion MAU | Dominant. Category-defining. | Feb 2026: 900M weekly active; ~1B MAU estimated. 5.5B web visits/month. The largest consumer AI product in history at current scale. |
| **Gemini (Google)** | ~900M MAU | Closing fast. | May 2026: 900M MAU for the Gemini app; 2B monthly via AI Overviews in search. Massive distribution advantage via Android/Search. |
| **Claude (Anthropic)** | ~30M MAU | Niche but high-value | ~18.9M web MAU + ~7.4M mobile MAU (third-party estimates); Anthropic does not publish a figure. Audience skews developers, researchers, power users — exactly the Tokenomics cohort. |

### New Candidate User Bases (Tier 1)

| Candidate | ~Consumer User Base | vs Claude | Notes |
|---|---|---|---|
| **Grok** | ~60M MAU | ~2x Claude's consumer web MAU | Third-most-used chatbot in the US as of Jan 2026, behind ChatGPT and Gemini. Predominantly consumer (X/Twitter users and grok.com direct). Enterprise penetration is minimal — see below. |
| **Perplexity** | ~45M MAU (core search) | ~1.5x Claude's consumer web MAU | 100M+ across all products including Comet browser and enterprise. Core search MAU is the relevant signal for quota-hitting behavior. 57% aged 18–34. |
| **ElevenLabs** | ~1M+ registered; ~558K mobile MAU | ~18x smaller than Claude | Revenue ($330M ARR) wildly exceeds what the MAU count implies — high monetization per user. Indie-dev / creator cohort is the Tokenomics audience. |
| **Leonardo.ai** | ~1.2M MAU; ~19M registered | Roughly comparable to Claude mobile MAU | 65%+ professional artists/studio teams. Acquired by Canva (2024), giving enterprise distribution. |

---

## Player Sizing and the Grok/Perplexity Audience Question

*Rob's hypothesis: "Only government/enterprise uses Grok and Perplexity — that's not a consumer market we want."*

**Verdict: Rob is wrong on both counts. Both Grok and Perplexity are consumer-majority products. The hypothesis does not hold.**

### Grok

Grok has an estimated 60–64M MAU (xAI internal data, late 2025; corroborated by third-party sources in early 2026). The demographic profile is clearly consumer: 50.87% under 35, 60% male, US + India as top markets. The user base is X/Twitter subscribers and grok.com direct visitors — social media users, not Office workers.

The enterprise story is the opposite of what Rob's hunch predicted. Enterprise penetration of Grok is negligible. A Netskope study of enterprise AI tool adoption (mid-2025) found only 2.6% of organizations had anyone using Grok at all, and only 0.02% of employees within those organizations used it monthly. Even after the Grok-3 release (early 2026), that number did not materially improve. xAI has government contracts (a $200M DoD contract, July 2025; GSA approval for federal procurement) and launched Grok Business/Enterprise tiers, but none of that has translated into meaningful enterprise seat counts. Grok is, today, a consumer chatbot used by X power users and AI enthusiasts — exactly the Tokenomics audience.

The real argument against Grok is not audience quality but audience loyalty: Grok's US chatbot share jumped from 1.9% (Jan 2025) to 17.8% (Jan 2026) primarily because xAI made it free inside X and aggressively promoted it to existing X Premium subscribers. That is distribution muscle, not product retention. Grok users may be more likely to churn than Claude or Perplexity users if xAI changes the free-tier terms. Worth tracking but not a reason to deprioritize the build.

**Bottom line on Grok: Consumer product, not enterprise. Rob's hunch is wrong. The 60M consumer MAU figure puts it at roughly twice Claude's consumer web footprint. Keep it Tier 1.**

### Perplexity

Perplexity is more nuanced. The platform reports 100M+ MAU across all products (April 2026), with ~45M on the core search product. The demographic is 57% aged 18–34 and predominantly individual users. That is clearly a consumer-heavy profile.

However, there IS a legitimate professional/enterprise dimension to Perplexity that does not exist for Grok: 64% of Perplexity users say they use it primarily for work, and the company claims 20,000+ enterprise clients. The GSA approved Perplexity Enterprise Pro for federal agencies in November 2025. This is a real enterprise footprint, unlike Grok's largely nominal one.

Critically for Tokenomics, "using it primarily for work" does not mean "enterprise seat." The typical Perplexity Pro user is an individual professional — a researcher, consultant, writer, student — paying $20/month out of pocket. These are exactly the people who complain loudly about Pro Search limits (recent Reddit threads document users hitting the Pro Search weekly cap as of May 2026, days after Perplexity quietly reduced limits). The quota pain is real, documented, and consumer-facing. Government procurement is a separate product (Enterprise Pro for Government) that does not show up in the consumer Web session quota.

There is one legitimate concern worth weighing: Perplexity's audience overlaps less with pure AI coders than Grok or ElevenLabs. The core Perplexity user hires the product to do research and answer questions, not to write code. This is a meaningful difference from the Tokenomics core cohort. The original roadmap scored audience fit at 4/5 (versus 5/5 for Grok) — that assessment is correct and the data supports it. The user base is real, consumer, and quota-frustrated; it just skews researcher-not-coder.

**Bottom line on Perplexity: Consumer product, not primarily enterprise or government. Rob's hunch is wrong. The enterprise story is real but it is a separate product tier that does not hit the consumer quota endpoint the reader would target. Keep it Tier 1, with the existing 4/5 audience-fit score (slightly lower than Grok/ElevenLabs because the research audience has less overlap with the Tokenomics coder cohort than the chatbot audience does).**

### Does the Data Change Any Tiering?

No. Both Grok and Perplexity stay Tier 1. The consumer audience evidence strengthens the case for both, particularly Grok. The original audience-fit scores (Grok 5/5, Perplexity 4/5) correctly captured the differential — Grok users are chatbot power users and AI coders; Perplexity users lean researcher — but both are clearly consumer-market products.

The one data point that might shift your build order is ElevenLabs' smaller raw MAU relative to Grok and Perplexity. However, ElevenLabs' audience is more precisely the Tokenomics cohort (indie devs, creative technologists) and its $330M ARR at ~1M registered users implies exceptional monetization — these are paying users who care about their tool, which correlates with wanting to track their quota. The original ordering (Grok → ElevenLabs → Perplexity → Leonardo.ai) holds.

---

## What Already Exists and What Changes

| Existing | Status | Notes |
|---|---|---|
| Claude (web) | Live | `claude.ai/api/organizations/{id}/usage`, real endpoint |
| ChatGPT (OpenAI) | Live | Local counter, `estimated: true` |
| Midjourney | Live | `/api/user-account`, real endpoint |
| Gemini consumer | Build-ready spec written | See `docs/gemini-reader-spec.md`. Spec confirmed against live endpoint (jSf9Qc batchexecute). Next step is Rob's go/no-go on `geminiConsumer` ProviderId and whether this rides beta-3 or beta-4. |
| Cursor (local) | Live in Mac app | Reads `state.vscdb`. The web-dashboard reader (Tier 2) is a separate data source — resolve which one is authoritative before building the web version. |
| Suno | Coming Soon in Mac enum | Coordinate extension reader with Mac pool when building. |
| Udio | Coming Soon in Mac enum | Same. Build after Suno validates the audio-reader audience. |

None of the new Tier 1 candidates (Grok, ElevenLabs, Perplexity, Leonardo.ai) conflict with existing providers — they are all new brands.

---

## Maintenance Reality Check

Every reader you ship becomes a monitoring obligation. The current set (Claude, ChatGPT, Midjourney) has already required one Midjourney endpoint correction after launch. Here is the realistic ongoing cost per reader type:

- **Real documented endpoint (ElevenLabs):** ~30 min/year to verify field names on major version bumps. Low.
- **Real undocumented endpoint (Grok, Perplexity, Gemini):** ~1-2 hrs/year when the provider changes their UI or resets the endpoint path. Medium. Must fail gracefully with a clear "sign in to check" state rather than silently showing zeros.
- **GraphQL session (Leonardo.ai):** ~2-3 hrs/year if schema changes; session token capture adds a periodic reverification step. Medium.
- **Endpoint confirmation pending (Bolt, Lovable, Ideogram, Udio, Cursor web):** Unknown until the DevTools spike. Could be low or high.
- **DOM scrape (anything that falls back to this):** Do not build. Every CSS class rename breaks it silently.

The DevTools spike protocol for Tier 2 pending-confirmation tools: open the provider's web app while logged in, open DevTools Network tab, filter by Fetch/XHR, navigate to the page that shows your usage/balance, look for a clean JSON response with a credit/quota/remaining field. If it exists and has stable-looking field names, promote to Tier 1. If it is only DOM rendering or a packed format like Google's batchexecute, make a deliberate call on whether to handle it.

---

## The Single Highest-Leverage Next Addition

**Grok** — if the goal is maximizing new high-value users acquired quickly.

ElevenLabs has a higher score in the table, but it requires one DevTools confirmation step (is the session-cookie endpoint the same as the documented `xi-api-key` endpoint?). Grok has zero open items: the endpoint is confirmed by multiple shipping tools, the auth pattern is identical to what the extension already does for Claude and Midjourney, and the user complaint volume around Grok limits is high and growing (xAI actively throttled paid SuperGrok users as recently as May 2026 — these are the exact users who search for "how many Grok queries do I have left").

Build Grok first. Do the ElevenLabs DevTools capture in parallel (15 minutes). If confirmed, ElevenLabs is build two. Perplexity is build three.

That sequence takes the extension from 3 providers to 6 (including Gemini consumer, which is already spec'd) without a single DOM scrape in the set.

---

## Future Workstreams (ordered, decided 2026-06-02)

The web readers are workstream #1. Two follow-ons, in priority order:

1. **Web readers (NOW)** — Grok, Perplexity, Leonardo (+ ElevenLabs auth fix). All captured against real endpoints. Worst-case UX: the user logs into the service on the web once, and the extension reads the account quota silently thereafter (the quota is account-wide, so it reflects desktop/mobile usage too).

2. **Desktop / native clients (NEXT)** — important for cognitive load: many users live in the Perplexity/Grok/Leonardo *desktop or mobile apps*, not the browser. The quota is the SAME account meter (not a separate pool), so the *number* is identical — the open problem is the *capture mechanism* when there's no browser session to read (read the native client's local store, or fall back to an API key / manual entry). This closes the coverage gap for desktop-only users.

3. **Developer-API spend (AFTER)** — a distinct, high-value area: the per-token, dollar-billed API pools (ElevenLabs `xi-api-key`, Perplexity Sonar, xAI API, Leonardo API `apiCredit`, OpenAI/Anthropic platform). This is real spend users want visibility into, and it dovetails with the team/enterprise spend-observability direction. Different metering (dollars, not refilling quota) and different read path (API key, not web session) — so it's its own surface, deliberately sequenced after consumer web + clients.

Capture-first is the rule for all of these: log into the real service, read the actual request via DevTools, then build the parser. Building blind on documented/assumed shapes burned cycles (Gemini's index order, ElevenLabs' cookie-vs-Firebase auth) — the live capture loop is faster end-to-end.
