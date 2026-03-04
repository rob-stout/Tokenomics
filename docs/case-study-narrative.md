# Tokenomics — Portfolio Case Study Narrative

**For:** Social media and marketing agents to use when crafting LinkedIn posts,
portfolio copy, or recruiter-facing materials.

**Audience:** Senior design leaders, product leaders, and hiring managers at
AI-forward companies including Anthropic. Also relevant to startup founders and
design-adjacent technical audiences.

**Date compiled:** 2026-03-04
**Project status:** Shipped. v2.2.2 live at github.com/rob-stout/Tokenomics. Full usage tracking for Claude Code, Codex CLI, and Gemini CLI.

---

## The One-Paragraph Summary

Tokenomics is a macOS menu bar app Rob designed and built from scratch that
tracks AI coding tool usage — Claude Code, Codex CLI, and Gemini CLI — as
concentric activity rings in the menu bar, inspired by Apple Watch. Developers
see at a glance whether they're about to hit a rate limit without opening a
browser tab. Rob conceived it, designed it, wrote every line of Swift, and
shipped it from a single-provider prototype to a three-provider system with
a clean protocol-based architecture. v2.2.0 is a working, signed, notarized,
auto-updating macOS app that any AI tool developer can install today.

---

## The Story Arc

### 1. The Problem

Claude Code charges by token consumption and enforces rolling rate limits across
two windows: a 5-hour short-term window and a 7-day longer-term window. The only
way to check your usage is to navigate to a browser, sign in, and find a usage
dashboard. For a developer in a coding flow, this is a friction-heavy context
switch that interrupts work at exactly the moment when you most need the
information.

The problem statement is precise: **a developer needs to know, without leaving
their keyboard, whether they have headroom to start a long agentic task.**

This is a glanceability problem, not an information architecture problem. The
data already exists. The interface was just in the wrong place.

### 2. The Approach

Rob's design process began with a platform choice rather than a visual design.
The menu bar is macOS's designated home for ambient, persistent, always-visible
utility apps. Weather, battery, CPU load, time — all live there. The decision to
build a menu bar app rather than a dashboard widget or a standalone window was
not aesthetic. It was the right answer to the problem statement: ambient
information with zero navigation required.

The visual metaphor was inspired by Apple Watch Activity Rings. Two concentric
rings — one for the 5-hour window, one for the 7-day window — fill clockwise as
token consumption grows, exactly as Activity Rings fill through the day. The
metaphor is culturally pre-loaded for any Apple user: fill the ring, don't fill
the ring. No legend required.

The pace indicator dot was the key insight that elevated the design from a usage
meter to a genuinely useful tool. A ring at 50% is meaningless without context:
is that good or bad? It depends on whether you're halfway through the window. The
pace dot shows where the fill *would* be if consumption were perfectly even
across the window. If your fill is ahead of the dot, you're burning faster than
average. If it's behind, you have room. This converts a raw number into
actionable signal — the difference between data and information.

### 3. The Build

The technical architecture is clean by deliberate choice. Rob uses SwiftUI
throughout and structures the codebase with strict separation between:

- **`UsageService`** — a Swift `actor` that owns the API call to
  `api.anthropic.com/api/oauth/usage`. An actor is the right concurrency
  primitive here because it isolates the network layer and prevents data races.

- **`PollingService`** — another actor that owns the 5-minute polling loop as a
  structured Task, with correct cancellation handling and an idempotent `start()`
  that prevents double-polling when the popover reopens mid-cycle.

- **`UsageViewModel`** — the `@MainActor` observable object that connects
  services to UI. It owns the token caching strategy: read from Keychain on
  launch, hold in memory, clear on 401, re-read Keychain before surfacing an
  error (because Claude Code silently rotates tokens during sleep/wake).

- **`KeychainService`** — reads Claude Code's OAuth token from the macOS
  Keychain without requiring any user setup. The token is stored by Claude Code
  itself in a large JSON blob. Rob discovered that macOS can truncate large
  Keychain items when read as parsed JSON, so the implementation extracts the
  access token via direct string pattern matching rather than JSON decoding —
  a pragmatic solution to an undocumented platform behavior.

- **`MenuBarRingsRenderer`** — draws the concentric rings directly in CoreGraphics
  as an `NSImage`, not in SwiftUI. This was a deliberate choice: the menu bar
  label needs to be an `NSImage` for proper template rendering (which allows
  macOS to invert the icon in dark mode and in active states automatically).
  The geometry maps precisely to a Figma component: 44px @2x = 22pt, with
  documented correspondence between Figma values and CoreGraphics drawing calls.

The distribution pipeline is encapsulated in a single shell script
(`scripts/distribute.sh`) that runs ten sequential stages: XcodeGen project
generation, archive, export, notarize app, staple ticket, create DMG, sign DMG,
notarize DMG, staple DMG, generate Sparkle appcast. This is the kind of
infrastructure that doesn't get talked about in portfolios but is the difference
between a project that ships once and a product that can be updated reliably.

### 4. The Craft

The v1.0 → v1.1 → v1.1.1 iteration story is where the design thinking becomes
most visible.

**v1.0 established the core:** rings in the menu bar, popover with usage bars,
Keychain-based zero-config auth.

**v1.1 was a systematic craft pass:**

- Removed color-shifting from the usage bars. The original bars changed from
  gray to orange to red as utilization climbed. But the fill amount already
  communicates state. Adding a simultaneous color shift introduced a competing
  visual signal without adding information. The principle: one variable per
  dimension.

- Added the pace indicator dot to the usage bars in the popover, mirroring the
  pace dots on the menu bar rings. This is not cosmetic. An experienced user who
  understands the ring metaphor will look for the same affordance in the expanded
  view. Inconsistency between surfaces breaks conceptual integrity.

- Animated bar fill on popover open, synchronized so both bars finish at the
  same moment regardless of their values. This required deliberately resetting to
  0 on `onDisappear` so the animation replays on every open — a non-obvious
  SwiftUI pattern that required multiple failed approaches before arriving at
  twelve lines of clean implementation.

- Moved secondary actions (Launch at Login, Check for Updates, About, Quit)
  behind a collapsible gear icon. The primary job of the popover is to show usage
  data. Settings competing for the same visual space violates information
  hierarchy. The pattern follows Fantastical, Bartender, and iStat Menus — apps
  with identical use cases and decades of combined polish.

- Designed the About view as a UI legend, not just credits. Every visual element
  in the app is explained in plain language. This solves the onboarding problem
  without cluttering the main UI with explanatory text.

- Moved the initial data fetch to app launch rather than first popover open.
  Previously, clicking the menu bar icon showed empty rings for a moment. This
  is the wrong first impression for a tool whose entire value proposition is
  instant information.

**v1.1.1 fixed three production bugs, each from a different category:**

- *Infrastructure:* The self-healing OAuth token retry. Claude Code rotates
  tokens during sleep/wake. The original 401 handler wiped the token and showed
  the login screen. The correct behavior: on 401, re-read Keychain first. If a
  fresh token is there, retry silently. Only surface the login prompt if the
  Keychain itself is empty. Users never see the rotation happen.

- *Copy:* "Resets today" vs. "Resets Friday." On Friday, showing "Resets Friday"
  is technically correct and practically useless. Two lines of code: if
  `isDateInToday`, show "Resets today." If `isDateInTomorrow`, show "Resets
  tomorrow." Otherwise, show the day name. This is the kind of edge case that
  doesn't make it into a spec because it seems too obvious to write down — and
  then ships wrong.

- *Math:* The pace dot disappearing intermittently. The API's reset timestamp
  was occasionally a few seconds past the assumed 7-day boundary, making elapsed
  time go slightly negative, which clamped to zero, which placed the dot at the
  start of the bar, where a visibility guard hid it entirely. The fix: cap
  `remaining` to `totalWindow` before computing elapsed, so the subtraction
  never goes negative. The v1.1.1 comment in `sevenDayPace` explains this
  reasoning in the code for any future maintainer.

### 5. The Reflection and What's Next

The multi-provider UX design document (`docs/multi-provider-ux.md`) was written
in February before the multi-provider build began. It analyzed three expansion
scenarios and made specific architectural recommendations. v2.2.0 shipped those
recommendations as working code — which means the document can now be read as
a record of design thinking that preceded and correctly predicted the
implementation, not as aspirational strategy.

The key insight — the "Weather App Model" — held: detect what's installed,
show the most relevant signal, make it trivial to see the rest. Tokenomics
v2.2.0 detects all three providers on launch without user configuration.

The "Worst-of-N" recommendation for the menu bar also shipped as specified.
`UsageViewModel.worstOfNUsage()` is five lines: filter connected providers,
compact-map their usage snapshots, take the max by `shortWindow.utilization`.
The popover handles per-provider breakdown via a tabbed segmented control that
appears only when multiple providers are active. Both rejected alternatives —
side-by-side micro-rings and cycling animations — were avoided for exactly the
reasons the document stated.

The `sublabelOverride` field on `WindowUsage` was the architectural invention
that made provider-specific sublabels work without touching the view layer.
Gemini shows "20.5K of 2.0M tokens today." Codex shows "230.7K of 258.4K
remaining." Claude shows "Resets in 4h 12m." The same `UsageBarView` renders
all three. The normalization happens at the model layer, not the view layer —
exactly as the strategy document specified.

One genuine surprise: Codex's `used_percent` field in its JSONL rate limit
events is always 0.0 — a confirmed CLI bug. The right data was in a different
event type entirely (`token_count`), which mirrors what the CLI itself shows
users. Shipping required forming a theory, testing it against actual session
files, and choosing the signal that was accurate rather than the one that was
labeled correctly. That's not a design or architecture problem. It's the kind
of empirical debugging that happens when you're working with undocumented
file formats from a third-party CLI.

**v2.2.2 was a language and documentation pass** that addressed a problem unique
to multi-provider UIs: the same visual element means different things depending
on which provider is active. The outer ring is the 7-day window for Claude, the
model context window for Codex, and the daily request cap for Gemini. The fix
was not a provider-specific legend — the About view is 320pt wide, not a
reference table — but behavioral language that holds across all three: "nearest
limit" (inner) and "broader context" (outer). Provider details appear as
secondary examples, not as the primary definition. The inner ring now appears
first in the legend because it's brighter, it's what the percentage tracks, and
it's what users act on. The legend follows attention order, not geometric order.

The About view also gained a Legal section — Privacy Policy and License links
that open in the browser — plus a non-affiliation disclaimer. These are the
minimum responsible legal affordances for a public app that reads credentials
from three major AI providers. The pattern (lightweight links, browser opens,
nothing displayed inline) follows established macOS utility app conventions.

The next meaningful expansion is a watch companion that surfaces the worst-of-N
signal on watchOS — the rings on your wrist, not the menu bar. The architecture
already supports it: `ProviderUsageSnapshot` is a pure value type with no
AppKit dependency, and `worstOfNUsage()` is already computed and available.

---

## What This Signals to Recruiters

### For any senior design role:

Rob does not just design artifacts — he ships products. Tokenomics is signed,
notarized, and publicly installable by any developer using AI coding tools. The
gap between "prototype I can demo" and "software strangers can install" is not
aesthetic; it requires solving auth, error handling, update distribution, and
code signing in ways that have nothing to do with visual design. Rob solved all
of them — and then expanded the product to cover three structurally different
providers without rebuilding the view layer.

The UX decisions throughout Tokenomics — the pace dot concept, progressive
disclosure of settings, the "Resets today" copy fix, the About-as-legend
pattern, the self-healing auth, the single-pin mode, the Gemini plan picker
that doesn't block usage — are all grounded in specific user mental models and
articulated trade-offs, not aesthetic instincts. This is what senior design
judgment looks like when it's applied to a real product instead of a prototype.

### For AI company roles, specifically Anthropic:

Tokenomics tracks usage across Claude Code, Codex CLI (OpenAI), and Gemini CLI
(Google) — the three tools most actively used by AI-assisted developers today.
Rob built tools that make all three more usable, understood their file formats
and authentication models well enough to decode usage data from each, navigated
undocumented platform behaviors (Keychain truncation, OAuth token rotation,
ISO 8601 fractional seconds, Codex JSONL rate-limit bugs), and then documented
the strategic path to a watch companion.

This is not a portfolio project that demonstrates AI tool familiarity. It is a
product that runs on Anthropic's, OpenAI's, and Google's infrastructure
simultaneously, solves a real problem for developers using those tools, and is
being actively iterated based on real-world usage patterns. The multi-provider
design document demonstrates that Rob is thinking about how AI developer tools
compete and coexist at the ecosystem level.

### For design leadership roles:

The portfolio-log entries at `docs/portfolio-log.md` are written as explicit
design rationale, not progress updates. Every decision has a named trade-off.
Every iteration is explained in terms of the principle it serves. The
distribute.sh script, the Sparkle appcast pipeline, the SwiftUI animation
patterns, the `sublabelOverride` escape hatch — Rob documents why each decision
was made, not just what it does. The note about scripting repetitive workflows
to preserve AI token budget is the kind of systems thinking that appears in
people who have run projects and teams, not just shipping individual features.

---

## Key Artifacts Available

| Artifact | What It Shows |
|---|---|
| Menu bar icon, all states (loading, live, error, unauthenticated) | Contextual state design and icon communication |
| Popover with three provider tabs active | Multi-provider navigation, single-surface design |
| `GeminiPlanSetupView.swift` | Non-blocking plan configuration; inline, no modal |
| Codex tab: "Context Window" bar with token sublabel | Choosing accurate signal over labeled-but-broken field |
| Gemini tab: dual bars — Requests Today + Tokens Today | Adapting view model to different provider data shapes |
| `DisplayModeMenuView.swift` | Smart vs. single-pin with radio behavior |
| `Provider.swift` — `UsageProvider` protocol + `WindowUsage.sublabelOverride` | Protocol design enabling three structurally different providers |
| `GeminiProvider.geminiDateStrategy` | Custom ISO 8601 date decoder; silent failure mode |
| `UsageViewModel.worstOfNUsage()` | Five-line Worst-of-N menu bar logic |
| `CodexProvider.parseLastSessionData` | JSONL tail-reading with 16KB window |
| `MenuBarRingsRenderer.swift` | CoreGraphics ring drawing, Figma-to-code correspondence |
| `UsageViewModel.swift` (self-healing token retry) | Architecture reflecting design intent |
| `WindowUsage.timeUntilReset` ("Resets today" logic) | Copy precision as UX |
| `distribute.sh` | 10-stage release pipeline; operational maturity |
| `docs/multi-provider-ux.md` vs. shipped v2.2.0 | Strategy doc as accurate prediction, not aspiration |
| `AboutView.swift` — inner/outer ring legend copy | Behavioral-first language pattern for multi-provider UIs |
| README "Menu Bar Icon Guide" with per-provider table | Progressive disclosure: primer in app, reference in docs |
| `docs/PRIVACY.md` | Formal privacy policy; signals production-grade responsibility |
| appcast.xml spanning v1.0 through v2.2.2 | Proof of sustained iteration across a product lifecycle |

---

## Quotes Worth Pulling

These are direct quotes from the portfolio-log and code comments that could be
extracted into LinkedIn copy, portfolio annotations, or recruiter conversations:

**On design judgment:**
"One visual variable (fill) is cleaner than two (fill + hue). The bar fill color
is now `Color.white.opacity(0.5)` — arrived at through four iterations
(0.9 → 0.7 → 0.6 → 0.5)."

**On conceptual integrity:**
"Parity between surfaces is not cosmetic — it's conceptual integrity."

**On architecture as design:**
"When model and view concerns are cleanly separated, removing the color-shifting
behavior later was a one-file change with no ripple effects. Architecture reflects
design intent."

**On shipping:**
"Shipping is a design decision. Many side projects reach 'functional' and stop
there."

**On the self-healing token fix:**
"The token wasn't invalid. It was just new. The app was destroying valid
credentials because it didn't distinguish between 'authentication failed' and
'this specific token is no longer current.'"

**On the copy fix:**
"This is the kind of thing that doesn't make it into a spec because it seems too
obvious to write down — and then ships wrong because nobody caught the edge case."

**On the distribution pipeline:**
"The asymmetry — high setup cost, near-zero marginal cost per release — makes
it the correct choice for any app expecting more than one version."

**On architecture holding through expansion:**
"The `UsageBarView` already accepts `label` and `sublabel` as parameters — it's
provider-agnostic. This means the view layer needs zero changes to support
Gemini's different windows. The normalization happens in a per-provider service."
(Written as prediction in the strategy doc. True in the shipped v2.2.0 code.)

**On choosing accurate signal over labeled signal:**
"The Codex rate limit `used_percent` is always 0.0. The `token_count` event
in the same file is accurate. I show what's accurate and useful, not what's
technically labeled as a rate limit."

**On silent failures:**
"Zero is the worst kind of wrong. Gemini's timestamps include fractional seconds
that Swift's default ISO 8601 decoder silently drops — producing plausible-
looking zero data rather than an error. The fix required knowing what to look for."

**On token budget and workflow automation:**
"When you're working with an AI coding assistant, the overhead of repetitive
infrastructure commands burns tokens on logistics rather than logic. Automating
release pipelines early is not just operational discipline — it is a force
multiplier on the token budget you have for actual feature work."

**On non-blocking configuration:**
"The Gemini plan picker doesn't block usage. The provider works at Free limits
in the background while the user reads the options. You can ship a good
experience before the user makes a choice."

**On copy as UX, not afterthought:**
"The rings worked correctly for all three providers before this session. But
the About view still described them in Claude-specific terms. The copy lagged
the code by one release cycle — not because it was forgotten, but because the
bug doesn't manifest at runtime."

**On behavioral language for multi-provider abstractions:**
"'Nearest limit' and 'broader context' hold true for all three providers. A
per-provider table in the About view would be accurate and wrong — accurate
as reference material, wrong as a first explanation."

---

## Suggested LinkedIn Post Angles

These are distinct angles the social/marketing agents can choose between or
combine. Each maps to a different audience segment.

**Angle 1: The Builder Story (broadest reach)**
A UX designer with 11 years of experience shipped a macOS app in a weekend.
Not a prototype. A signed, notarized, auto-updating product. Here is how the
design thinking shows up in three specific decisions... [use "Resets today" fix,
pace dot, progressive disclosure settings]. Call to action: download link.

**Angle 2: The Craft Story (design leaders)**
The gap between working software and shippable software is craft. Here are
three things I changed in v1.1 that had nothing to do with features... [pace
dot parity, settings behind gear, data loads at launch]. Punchline: "None of
them are dramatic. Together they make the difference between a side project and
a product."

**Angle 3: The Technical Story (engineers and founders)**
Building for the Claude ecosystem forced me to solve three specific technical
problems that don't appear in any tutorial... [Keychain truncation workaround,
self-healing OAuth retry, CoreGraphics template image for menu bar]. This is
what it actually costs to ship a macOS app that's invisible when it's working.

**Angle 4: The Strategy Story (Anthropic and AI companies)**
I built a tool on top of Claude's API. Then I documented what it would take to
support OpenAI Codex and Gemini too. The design insight: the menu bar is a
warning system, not a dashboard. "Worst-of-N" — always show the most constrained
provider — is the right answer for a 50px ambient display. Here is why the
alternatives fail... [side-by-side rings too small, cycling animations break
glanceability].

**Angle 5: The Iteration Story (anyone who builds things)**
Three bugs. Three categories. This is what a 1.x quality pass actually looks
like... [infrastructure: self-healing auth, copy: "Resets today", math: pace dot
negative elapsed]. One paragraph per bug. Punchline: "The app is better for it."
(Note: this angle is already drafted as the v1.1.1 LinkedIn post in
`/Users/jarvis/projects/Tokenomics/linkedin-post.md`.)

**Angle 6: The Multi-Provider Build Story (v2.2.0 — engineers and product people)**
I wrote a design doc in February predicting exactly how the multi-provider
architecture should work. Then I shipped it. Here is what the spec said,
and here is what the code actually looks like... [UsageProvider protocol,
sublabelOverride field, worstOfNUsage()]. The interesting part: the strategy
doc was right about the architecture and wrong about one thing — I thought
Codex would show rate limits. It shows a context window instead, because
the rate limits in Codex's JSONL files are all 0.0. You find this out by
reading actual files, not by reading docs.

**Angle 7: The Silent Failure Story (engineers and developers)**
I spent an afternoon debugging Gemini showing zero usage. Every session file
was parsed correctly — no errors, no crashes. Just zero. The bug: Swift's
default ISO 8601 date decoder silently ignores fractional seconds. A timestamp
like `2026-03-03T16:02:55.528Z` parses as nil. No exception. Just nil.
Every session filtered out as "before today" because nil timestamps compared
wrong. Fix: custom DateDecodingStrategy with .withFractionalSeconds. Lesson:
zero is the hardest kind of wrong to debug, because it looks like correct
empty data.

**Angle 8: The Token Budget Story (AI tool users and developers)**
I used an AI assistant to build an app that tracks AI assistant usage. The
meta-lesson: the distribute.sh script I built to automate the release pipeline
saved more tokens than any single feature I shipped. Every release without it
would have been 15–20 back-and-forth exchanges just on build infrastructure.
With it, it's one command. If you're building with AI coding tools, automate
your repetitive workflows before your features — not after. The token budget
you save is the one you get to spend on actual problems.

**Angle 9: The Language as UX Story (design leaders and PMs)**
When I added Codex and Gemini support, the rings broke — not visually, but
linguistically. The outer ring was the "7-day window" in the docs. That's true
for Claude and meaningless for Codex (context window) and Gemini (daily
requests). The fix wasn't a per-provider table. It was finding language that
holds for all three: "nearest limit" (inner) and "broader context" (outer).
Provider details come second. The lesson: in multi-provider UIs, behavioral
descriptions outlive implementation-specific ones. Write for what it does,
not which API it calls.
