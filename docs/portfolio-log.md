# Tokenomics — Portfolio Log

Tokenomics is a macOS menu bar app that visualizes Claude Code API usage
as concentric rings, inspired by the Apple Watch Activity Rings. It polls
the Claude API and renders two rate-limit windows (5-hour and 7-day) as
live, animated arcs directly in the menu bar.

---

## 2026-03-04 — v2.2.2: Ring Description Redesign and Documentation Clarity

**Phase**: The Craft — language as UX, and the work of making multi-provider abstractions legible

**What I Did**: Rewrote how the app explains itself — About view, README, and inline copy — to accurately describe rings that mean structurally different things across three providers. Added a Legal section to the About view with Privacy Policy and License links. Shipped formal legal and supporting documentation (PRIVACY.md, overhauled LICENSE). Released as v2.2.2.

**Why It Matters**: When you support three providers, the ring metaphor that was self-evident for Claude becomes genuinely ambiguous. The outer ring is the 7-day window for Claude, the model context window for Codex, and the daily request cap for Gemini. Calling it the "7-day ring" in the About view is accurate for one provider and wrong for two others. The solution was not a per-provider table in the About view — a 320pt popover is the wrong surface for a lookup table — but behavioral language that holds true regardless of provider: "nearest limit" (inner) and "broader context" (outer). Provider specifics follow as secondary reference. This is a content architecture decision disguised as copy editing.

**Key Decisions**:

1. **Behavioral description first, provider specifics second.** The inner ring is always "your most immediate constraint — the limit you're closest to hitting." The outer ring is always "the broader picture — a longer-horizon or secondary metric." Those definitions hold for Claude, Codex, and Gemini. Provider-specific details (5-hour rate limit, context window, daily requests) appear afterward as examples, not as the primary definition. This matches how users actually encounter the app: they learn what the rings *mean* first, then map that meaning onto whichever provider they're using. Reversing the order would require users to hold three rows of a table in their head before they understand the metaphor.

2. **Inner ring listed first in the legend.** The original legend described the outer ring before the inner ring, following the visual order of the rings from outside in. I flipped it: inner ring first, outer ring second. The reason: the inner ring is brighter, the percentage in the menu bar always reflects the inner ring, and it's the constraint users act on. The legend should follow the user's attention order, not the geometric order. Small change, correct reading sequence.

3. **Progressive disclosure between About view and README.** The 320pt About view teaches visual grammar (what rings mean behaviorally) and links to full documentation. The README carries the complete per-provider lookup table — same information architecture, different execution per surface. The About view is a primer; the README is a reference. Designing these as distinct surfaces with distinct jobs avoids cramming reference-level detail into an onboarding context.

4. **"Only shown on time-based windows" for the pace dot.** The original pace dot description implied it appeared everywhere. A Codex user would never see a dot on the context window ring and would assume something was broken. Added the caveat explicitly. The correct behavior was already in the code — this was copy catching up to implementation. A small distinction, but the kind that prevents a support question that begins "the dot disappeared."

5. **Gemini plan labeled as user-selected.** The Plan Badge description now distinguishes between Claude/Codex (auto-detected) and Gemini (user-set). Gemini's daily limits are estimates derived from the user's selected plan because Google enforces tokens-per-minute, not tokens-per-day. Surfacing this asymmetry in the UI copy prevents the confusion of a user asking why their Gemini numbers don't match their actual usage exactly. Honesty about the estimate is better UX than false precision.

6. **Legal section in About view as lightweight browser links.** Added Privacy Policy and License links that open in the default browser. The decision to link out rather than display inline was easy: a 320pt popover is the wrong container for legal documents. The right interaction pattern for utility popover apps — consistent with Fantastical, iStat Menus — is a link that takes you elsewhere. Also added the non-affiliation disclaimer ("Tokenomics is not affiliated with, endorsed by, or sponsored by Anthropic PBC, OpenAI Inc., or Google LLC.") as a small `caption2` string in the About footer — where it can be read once and ignored thereafter.

**What I Learned**: Writing copy for multi-provider UIs reveals information architecture problems that don't surface during implementation. The rings worked correctly in code for all three providers before this session. But the About view still described them in Claude-specific terms, which was accurate for the original single-provider design and wrong the moment Codex and Gemini shipped. The copy lagged the code by one release cycle — not because it was forgotten, but because the bug doesn't manifest at runtime. Treating copy as a first-class design artifact, not an afterthought, means reviewing it at the same time you review UI changes, not separately.

On the legal and strategy side: the source-available licensing decision deserves one sentence here. The value of Tokenomics as a portfolio artifact is design craft, not code IP. MIT would be more permissive, but source-available preserves monetization optionality for future paid tiers — a paid watch companion, a team plan — without blocking individual professional use. Keeping the repo public serves portfolio visibility. The license threads that needle.

**Artifacts to Capture**:
- Screenshot: About view showing the final ring legend order (Inner Ring first, Outer Ring second) with the Legal section visible at the bottom
- Screenshot: README "Menu Bar Icon Guide" section — the `inner / outer / track / dot` ASCII diagram with the per-provider table below it
- Side-by-side: old About view outer-ring-first order vs. new inner-ring-first order — shows the reasoning about attention sequence
- Code snippet: `AboutView.swift` lines 58–77 — the inner/outer ring `legendRow` definitions with their final copy; shows behavioral-first language pattern
- `docs/PRIVACY.md` — the formal privacy policy as a shipped artifact; relevant for any future App Store or enterprise deployment discussion

**Story Thread**: This entry belongs to "The Craft" arc — specifically the part of craft that deals with language rather than visuals. Every earlier craft pass in this project improved something visual or interactive: color variables, animation timing, progressive disclosure of settings. This pass improved the words. The About view is the app's onboarding surface — it's where a new user goes when the rings don't yet make sense. Getting the language right is not documentation work. It's UX work.

---

## 2026-03-09 — Widgets, IA Redesign, and Rate Limit Defense

**Phase**: The Craft — platform constraints, information architecture, and resilient data fetching

**What I Did**: Shipped a macOS WidgetKit extension with two configurable widget families, redesigned the app's information architecture by splitting "About Tokenomics" into two purpose-driven screens, and implemented a three-layer defense against Anthropic's OAuth rate limit bug. Each of these was driven by a distinct problem — discoverability, user intent mismatch, and silent data staleness — not by a feature roadmap.

**Why It Matters**: Widgets extend the app's core concept — ambient usage awareness — to the desktop surface users actually stare at between coding sessions. The IA redesign reflects a principle I use in product work constantly: content designed for two different user intents (confused vs. curious) cannot live comfortably on the same screen. And the rate limit defense demonstrates that graceful degradation is a design problem as much as an engineering one — the right question isn't "what do we show when the API fails?" but "how do we make the failure invisible to users who don't need to know about it?"

**Key Decisions**:

1. **File-based App Group storage over UserDefaults for widget data.** The main app is non-sandboxed (it reads credential files from `~/.claude/`, `~/.codex/`, `~/.gemini/`). Widget extensions must be sandboxed. `UserDefaults(suiteName:)` uses CFPreferences, which behaves unreliably when one process in a shared suite is sandboxed and one is not. The solution was file-based storage in the shared App Group container — the main app writes a JSON snapshot, the widget reads it. This is a more explicit contract than UserDefaults and sidesteps the CFPrefs sandbox boundary entirely. The trade-off: a small amount of serialization code that UserDefaults would have handled automatically. Worth it for the reliability.

2. **App sandbox entitlement required for widget gallery visibility.** This is undocumented. A widget extension that appears structurally correct — correct Info.plist, correct entitlements for App Group, correct widget timeline provider — will not appear in the macOS widget gallery if the `com.apple.security.app-sandbox` entitlement is absent. No error is surfaced; the widget simply doesn't show up. Discovering this required testing on a clean install, not a simulator. The fix is a one-line entitlements addition, but finding it cost time that better documentation would have prevented.

3. **"Smart" mode as a widget configuration option.** The widget's `AppIntent` lets users choose between Smart (worst-of-N utilization across all installed providers) or a specific provider (Claude, Codex, Gemini). This mirrors the menu bar's Smart vs. pin behavior. The key insight: a small widget has one number to show, and the worst-of-N utilization is the number that requires action. Defaulting to Smart means the widget is useful immediately after install, without configuration. The provider-specific options exist for users who want to watch a single tool.

4. **Split "About Tokenomics" into "How It Works" and "About Tokenomics."** The monolithic About screen was serving two different jobs simultaneously: (a) helping confused users understand the UI, and (b) telling the story of what the app is and who built it. Users in state (a) are scanning for a specific answer — they want a legend, a quick explanation of the ring metaphor, how data is fetched. Users in state (b) are reading a short narrative — they want identity, provenance, a link to learn more. Scanning and narrative reading are different cognitive modes, and combining them on one screen means neither job gets done well. The split was recommended by a designer agent and refined based on my input: keep the version number in the Quit row (it's utility context, not marketing), avoid "open source" language in favor of a direct portfolio link.

5. **Desktop Widgets explainer moved from Settings to How It Works.** The explainer for the macOS "access data from other apps" permission dialog was previously a paragraph of explanatory text living inside a Settings list of action rows — a clear affordance mismatch. Action rows prompt behavior; explanatory text teaches. Moving it to How It Works put it next to the other conceptual explanations (how rings work, how data is fetched), where a user who encounters the permission dialog will naturally look for context.

6. **Three-layer rate limit defense for Anthropic's OAuth endpoint.** Anthropic's usage endpoint has a known bug: approximately 5 requests per OAuth token before returning 429. The layered response: (a) proactive token refresh every ~22 hours, staying ahead of the per-token limit before hitting it; (b) reactive refresh on any 429 response as a recovery path; (c) cached data fallback with "Updated Xm ago" microcopy when both strategies fail. This is deliberate systems thinking — no single layer is sufficient, but together they make the failure invisible in normal use.

7. **"Updated Xm ago" as the stale data signal.** The original stale data indicator was "Rate limited · showing cached data" — accurate but alarming. It implies failure and invites the user to question whether the data is trustworthy. The replacement, an orange-tinted "Updated Xm ago" with a tooltip, communicates the same information without the negative frame. "Updated 4m ago" is how weather apps, dashboards, and news feeds handle stale data. It implies the system is working and gives the user a simple way to assess the data's age. Microcopy that informs without alarming is a design choice, not a euphemism.

**What I Learned**: The widget gallery discoverability bug (missing sandbox entitlement) is a good example of how platform constraints can be invisible until you test in the right context. Simulator testing wouldn't have caught it. This is a category of problem that shows up repeatedly in mobile and desktop platform work: the gap between "builds without error" and "works for users" is often a deployment-context issue, not a logic issue. The solution is always some version of testing in the most production-like environment available, earlier than feels necessary.

The IA split reinforced something I use in design work but don't always articulate cleanly: the right question for any screen or surface is "what is the user's intent when they arrive here?" Not "what information do we have?" Not "what do we want them to know?" When intent is well-defined, content organization becomes obvious. When intent is ambiguous or composite, the screen fights itself.

**Artifacts to Capture**:
- Screenshot: small widget in macOS widget gallery — ring showing worst-of-N utilization
- Screenshot: medium widget — multi-provider dashboard with all three providers visible
- Screenshot: widget configuration interface — Smart vs. specific provider AppIntent
- Screenshot: How It Works screen — legend, data fetching explanation, Desktop Widgets explainer
- Screenshot: About Tokenomics screen — identity narrative, Rob Stout portfolio link, Buy Me a Coffee
- Side-by-side: old monolithic About screen vs. the two new purpose-driven screens
- Screenshot: "Updated Xm ago" stale data indicator with orange tint vs. old "Rate limited" message
- Code snippet: App Group file-based storage write/read pattern — shows the explicit serialization contract that sidesteps the CFPrefs sandbox issue
- Code snippet: three-layer token refresh logic — proactive 22-hour refresh, reactive 429 handler, cached fallback
- Diagram: widget data flow — main app writes JSON to App Group container → widget extension reads on timeline refresh

**Story Thread**: This entry sits at the intersection of "The Build" and "The Craft" arcs. The widget extension is new surface area — the concept of ambient usage awareness now lives on the desktop, not just in the menu bar. The IA redesign and microcopy decisions are pure craft — small choices with measurable impact on how the app feels to someone who doesn't know how it works yet. The rate limit defense is engineering in service of design: the goal was never to handle a 429 correctly, it was to make the API's instability invisible to users who shouldn't have to think about it.

---

## 2026-03-09 — v2.2.6: Homebrew Cask Distribution

**Phase**: The Build — distribution strategy as a user experience decision

**What I Did**: Added a Homebrew Cask installer as a parallel distribution channel alongside the existing direct DMG download. Users who prefer the terminal can now install with `brew install --cask tokenomics` and receive the same signed, notarized binary as the DMG path.

**Why It Matters**: Distribution is a UX decision. The target users for Tokenomics are developers who spend their working day in the terminal — they installed Claude Code, Codex CLI, and Gemini CLI from the command line, they manage their tools with package managers, and they are mildly annoyed by anything that breaks that pattern. Offering only a DMG download is a small friction point that accumulates: find the GitHub release page, click download, open the DMG, drag to Applications, eject, dismiss Gatekeeper. For a developer, `brew install --cask tokenomics` followed by a return key is not a convenience — it is the expected path. Offering a Homebrew Cask is meeting your audience in their environment, not asking them to step into yours.

**Key Decision**: Support two distribution channels rather than consolidating on one. The trade-off is maintenance overhead — both the DMG and the Cask formula need to be updated on each release — against adoption friction for the primary user persona. The overhead is small (the Cask formula is a short file that references the same GitHub Release asset already being published) and the friction reduction is real. The correct answer for a developer tool targeting developers is to have both. A direct download link matters for discoverability (GitHub search, web search, landing pages). A Homebrew Cask matters for the moment of installation.

**What I Learned**: The decision exposed a broader principle: distribution channels are not fungible. Each channel carries its own trust signal and workflow affordances. A DMG on a GitHub release page signals "this is a real macOS app from a developer who knows the platform." A Homebrew Cask signals "this is a first-class developer tool that someone cared enough to package for the ecosystem I already use." The same binary, two different signals, two different adoption contexts. Thinking about distribution at the level of "who is the user and what is their workflow" rather than "what is the path of least effort for the developer" is the same kind of reasoning I apply to onboarding flows and settings screens. It just showed up here in a shell command.

**Artifacts to Capture**:
- The Homebrew Cask formula file — short, concrete artifact that makes the decision tangible
- README section showing both installation paths side by side (`brew install --cask` and DMG download) — shows that the decision was treated as a first-class UX choice, not a footnote
- Screenshot: GitHub Release page showing the DMG asset alongside a note about the Cask — illustrates the two-channel strategy visually

**Story Thread**: This entry belongs to "The Build" arc, but specifically the part of building that concerns how software reaches its users rather than how it works internally. Most solo developer projects treat distribution as an afterthought — ship the binary, post the link, done. Treating the install command as a product decision is what distinguishes a developer tool from a developer experiment.

---

## 2026-03-03 — v2.2.0: Multi-Provider Expansion (Gemini + Codex, Real Data)

**Phase**: The Build — shipping the multi-provider vision designed in the strategy doc

**What I Did**: Shipped full usage tracking for all three AI coding tools — Claude Code, Codex CLI, and Gemini CLI — in a single release. Gemini required parsing local session JSON files and implementing a plan-selection flow since Google's CLI exposes no API. Codex required reverse-engineering which signal to trust: the JSONL session files contain a rate_limit `used_percent` field that is always 0.0 (a confirmed CLI bug), while a separate `token_count` event accurately reflects the context window remaining — the same "95% left" figure the CLI shows in the terminal. Both providers feed the same `UsageProvider` protocol and render through the same `UsageBarView`, exactly as the multi-provider UX spec intended.

**Why It Matters**: The original case study narrative described a planned multi-provider architecture. This release proves the architecture was sound. The `UsageProvider` protocol, `ProviderUsageSnapshot` shape, and `sublabelOverride` field on `WindowUsage` absorbed three structurally different data sources — API polling, JSONL file parsing, and JSON session file traversal — without the view layer needing modification. Designing for future extensibility and then actually shipping the extension are two different claims. This makes them the same claim.

**Key Decisions**:

1. **Gemini: ask the user once, don't block on absence.** Google's Gemini CLI has no API to detect the user's plan tier. The options were: block the provider until the user configures it, use a hardcoded default, or ask once inline and then remember. I chose the third path. The `GeminiPlanSetupView` appears inline the first time a user selects the Gemini tab — it replaces the usage content without a modal sheet, preserving the popover geometry. The provider defaults to the Free plan in the background, so detection and basic counting begin immediately. The plan badge is tappable to change the selection at any time. This is the minimum friction path for a setting that most users will set once and never touch again.

2. **Codex: show context window, not rate limits.** The Codex JSONL rate limit `used_percent` field is always 0.0. Investigation confirmed this is a CLI-side bug — the value populates later in long sessions but starts at zero. The `token_count` event in the same JSONL files, however, accurately reports how many tokens are loaded into the context window versus the model's maximum. This is also the number the CLI itself shows users ("95% context remaining"). The decision: display what's accurate and useful, not what's technically labeled as a rate limit. The `shortWindow` bar shows context window fill with a sublabel formatted as "230.7K of 258.4K remaining" — specific, honest, and matches what the CLI shows.

3. **Single-pin mode replaces multi-pin.** The earlier design allowed pinning multiple providers to the menu bar simultaneously, each rendering its own ring set. In practice, `MenuBarExtra` has a hard width cap of roughly 80–100pt. Two ring sets plus labels overflows it. The fix was to replace multi-pin with radio-button behavior: you can pin exactly one provider, or let Smart mode (worst-of-N utilization) decide. The `DisplayModeMenuView` uses `pin.fill` to indicate a pinned state and `circle.circle` for Smart mode. Simpler mental model, same power, fits the constraint.

4. **`sublabelOverride` on `WindowUsage`.** The original `WindowUsage` struct computed its own sublabel from reset timestamps ("Resets in 4h 12m"). Gemini and Codex have different information to show: request counts, token counts, no meaningful reset time. Rather than making each provider subclass or wrap the view, I added an optional `sublabelOverride: String?` field to `WindowUsage`. If present, it replaces the computed reset string. The model layer computes the right string for each provider; the view layer doesn't know it exists. One field, no new protocol requirements, clean boundary.

5. **ISO 8601 fractional seconds — a silent failure.** The Gemini session files use timestamps like `2026-03-03T16:02:55.528Z`. Swift's default `.iso8601` `JSONDecoder.DateDecodingStrategy` does not handle fractional seconds. Every session file was failing to parse, silently, returning an empty array and showing 0 usage. The fix required a custom `DateDecodingStrategy` using `ISO8601DateFormatter` with `.withFractionalSeconds` option, plus a fallback for timestamps without fractions. The lesson: Swift's date parsing has an undocumented silent failure mode that produces plausible-looking zero data rather than an error. Zero is the worst kind of wrong.

6. **Terminal reuse via AppleScript.** The install and login flows previously opened `.command` files, which always spawn a new Terminal window. During a normal coding session this produces window clutter that feels like the app lost control of the user's desktop. Replaced with AppleScript `do script ... in front window`, which runs the command in the user's existing Terminal window when one is open. Falls back to `.command` file if the AppleScript fails. One small change, measurable reduction in perceived disruption.

7. **Source-available license.** Replaced MIT with a custom license: free to use and share with attribution, no commercial redistribution. Strategic reasoning: the repo needs to stay public for portfolio visibility and user trust (open source is a meaningful signal for macOS apps from an unknown developer), but MIT gives commercial actors a free pass to redistribute without credit. The custom license preserves public visibility while closing that gap.

**What I Learned**: The most important meta-lesson in this release is about token budget management. The `distribute.sh` script handles the entire build/sign/notarize/DMG/appcast pipeline in one command. During this session, every build was triggered via that script — no manual back-and-forth with the AI assistant to re-explain the build pipeline. The implication is broader than this project: when you're working with an AI coding assistant, the overhead of repetitive infrastructure commands burns tokens on logistics rather than logic. Automating release pipelines early is not just operational discipline — it is a force multiplier on the token budget you have for actual feature work. Identify the multi-step workflows that appear in every session. Script them. Do this before the features, not after.

On the Swift side: `.contentShape(Rectangle())` is essential for any SwiftUI button where only text is rendered — without it, only the glyphs are tappable. The `.id()` modifier on `providerContent` forces SwiftUI to destroy and recreate the view on tab switch, resetting `@State` animation values that would otherwise persist stale across providers. Neither of these is obvious from documentation; both caused real bugs before the fixes.

**Artifacts to Capture**:
- Screenshot: popover with all three provider tabs visible (Claude Code / Codex CLI / Gemini CLI)
- Screenshot: `GeminiPlanSetupView` inline — plan selector with limit summary below the picker
- Screenshot: Codex tab showing "Context Window" bar with "230.7K of 258.4K remaining" sublabel
- Screenshot: Gemini tab showing dual bars — "Requests Today" and "Tokens Today"
- Screenshot: `DisplayModeMenuView` open — Smart vs. pin options with checkmark/pin icon
- Code snippet: `GeminiProvider.geminiDateStrategy` — the custom date decoder with fractional seconds fallback
- Code snippet: `WindowUsage.sublabelOverride` field and `timeUntilReset` computed property — shows the escape hatch pattern
- Code snippet: `UsageViewModel.worstOfNUsage()` — five lines implementing the Worst-of-N menu bar logic
- Code snippet: `CodexProvider.parseLastSessionData` — JSONL tail-reading pattern with 16KB window
- Diagram: data flow for all three providers converging at `ProviderUsageSnapshot` → `PopoverView`

**Story Thread**: This entry completes "The Build" arc at the multi-provider scale. The strategy document written in late February described how this should work in theory: detect installed tools, normalize to a common data shape, render through a provider-agnostic view layer. This release shipped that theory as working, notarized, auto-updating software. The pace dot is now drawn for Gemini's token consumption. The rings in the menu bar reflect the most constrained of three providers. The architecture held.

---

## 2026-02-27 — Case Study Narrative: Documenting the Full Arc

**Phase**: The Reflection — making the work legible to the outside world

**What I Did**: Conducted a full retrospective documentation pass across the
entire Tokenomics project — codebase, git history, portfolio log, LinkedIn post
drafts, and the multi-provider UX strategy document. Produced a comprehensive
case study narrative at `docs/case-study-narrative.md` that structures the
project as a portfolio story with five defined arcs: Problem, Approach, Build,
Craft, Reflection.

**Why It Matters**: Building is one skill. Making the thinking behind the build
legible to someone who wasn't in the room is a different skill, and it's the
one that matters for job searching. The code, the design decisions, and the
iteration story all exist in the codebase — but scattered across source files,
commit messages, and log entries, they don't tell a story on their own. The
narrative assembles them into a coherent arc that a recruiter or design leader
can read in five minutes and understand what kind of designer and builder Rob
is.

**Key Decision**: Organized the narrative around five post-level angles (Builder
Story, Craft Story, Technical Story, Strategy Story, Iteration Story) rather
than one unified narrative. The reasoning: different audiences at different
companies need different entry points. A design leader at Anthropic cares about
the strategic multi-provider thinking. A startup founder cares about the
build-and-ship story. A fellow designer cares about the craft decisions. One
document serves all five by separating the source narrative from the delivery
angle — the social and marketing agents can choose the framing without
duplicating the research.

**What I Learned**: The most compelling portfolio moments are not the ones that
went smoothly — they're the ones that reveal judgment under constraint. The
self-healing OAuth retry, the "Resets today" copy fix, and the pace dot
disappearing-due-to-negative-elapsed-time bug are each small, but each reveals
a different dimension of how Rob thinks: infrastructure thinking, copy precision,
and mathematical edge-case analysis. A portfolio that only shows polished
outcomes doesn't show thinking. Showing what broke and how it was reasoned
through is more valuable.

**Artifacts to Capture**:
- `docs/case-study-narrative.md` — the primary source document for all
  downstream portfolio and social content
- The five "Suggested LinkedIn Post Angles" in the narrative — each is a
  discrete post brief that a social agent can execute independently
- The "Quotes Worth Pulling" section — these are exact lines from the codebase
  and portfolio log that can be used verbatim in portfolio annotations

**Story Thread**: This entry closes "The Reflection" arc at the v1.x stage. The
project is documented. The thinking is preserved. The story can now be told to
people who weren't there — which is, ultimately, what a portfolio is for.

---

## 2026-02-25 — Quality Pass: From Working Software to Shippable Product

**Phase**: The Craft — polish, consistency, and production readiness

**What I Did**: Ran a senior code review against the full codebase, then
systematically addressed every finding across three dimensions: visual
design, interaction quality, and engineering hygiene. The result was not
a single new feature but a coordinated set of improvements that moved the
app from "functional prototype" to something I'd be comfortable putting a
version number on.

**Why It Matters**: There's a meaningful gap between software that works
and software that's ready to ship. This session was about closing that
gap — treating the app the way I'd treat a design file before a client
handoff: consistent, legible, with nothing left unresolved. The discipline
of doing this pass before adding more features is itself a design decision.

**Key Decisions**:

1. **Removed color-shifting from the usage bars.** The original bars
changed from gray to orange to red as utilization climbed — the same
semantic logic as the menu bar rings. But the bars already communicate
state through fill amount. Adding a simultaneous color shift introduced a
second signal competing for attention without adding information. I cut it.
One visual variable (fill) is cleaner than two (fill + hue). The bar fill
color is now `Color.white.opacity(0.5)` — arrived at through four
iterations (0.9 → 0.7 → 0.6 → 0.5) — which sits more naturally inside
the vibrancy-backed popover than any semantic gray.

2. **Added the pace indicator to the usage bars.** The menu bar rings
already had pace dots showing "where ideal even usage would be at this
moment." The dropdown bars didn't. That inconsistency would confuse anyone
who understood the ring metaphor and then opened the panel. A solid white
circle the same diameter as the bar height now appears at the pace
position on each bar, using the same mathematical definition as the ring
dots (`elapsed / totalWindow`). Parity between surfaces is not
cosmetic — it's conceptual integrity.

3. **Animated bar fill on popover open.** Both bars animate from empty to
their live value over a fixed 0.5s ease-out every time the popover opens.
The key constraint was using a fixed duration for both bars rather than
per-value timing — so a bar at 30% and a bar at 80% finish at the same
moment. This required deliberately animating from 0 on `onAppear` and
resetting to 0 on `onDisappear` so the animation replays on every open.
Several intermediate approaches failed: one caused the animation to bleed
into the whole popover, another didn't replay. The final implementation is
twelve lines and no SwiftUI hacks.

4. **Settings behind a gear icon.** Launch at Login, Check for Updates,
About, and Quit were visible by default in an earlier version. The
designer in me knew this was wrong: these are secondary actions that
should not compete with the primary content (usage data). I moved all of
them behind a collapsible section triggered by a gear icon in the footer.
This follows the exact pattern used by Fantastical, Bartender, and iStat
Menus. The popover is shorter and calmer by default; power users find what
they need where they expect it.

5. **About page as a UI legend, not just credits.** The About view
explains every visual element in the app: what the outer ring means, what
the inner ring means, what pace dots are, what the white bar dot means,
what the plan badge indicates, what extra usage is. This was a deliberate
choice to lower the learning curve without burdening the main UI with
explanatory text. The About view replaces the main popover content
inline — no sheet, no separate window — so the corner rounding and window
geometry stay identical.

6. **Polling moved to app launch.** Previously the app fetched data on
first popover open. That meant clicking the menu bar icon showed empty
rings for a moment before data appeared. Moving `startPolling()` to
`MenuBarLabel.onAppear` means the rings are live before the user ever
opens the panel.

**What I Learned**: The `UsageState.color` property started as a model
concern (`UsageData.swift`) and I moved it to a view extension
(`UsageBarView.swift`). That sounds mechanical, but it surfaces something
real: the model doesn't need to know how it's displayed. When model and
view concerns are cleanly separated, removing the color-shifting behavior
later was a one-file change with no ripple effects. Architecture reflects
design intent.

On the auto-update side: integrating Sparkle via Swift Package Manager was
the first time I built a full software distribution pipeline — EdDSA key
generation, code signing, notarization, DMG creation, appcast XML
generation, and hosting on GitHub. The pipeline is encapsulated in a
`distribute.sh` script so future releases are a single command. This is
the kind of infrastructure a solo developer has to build once and never
think about again.

**Artifacts to Capture**:
- Screenshot: menu bar in multiple states (loading, live data, error,
  unauthenticated) — shows contextual icon and tooltip behavior
- Screenshot: popover closed/default state vs. settings expanded — shows
  the progressive disclosure before/after
- Screenshot: About view with the full UI legend
- Screenshot: usage bars with pace indicator dot vs. without (before/after)
- Code snippet: `UsageBarView.swift` — the `onAppear`/`onDisappear`
  animation reset pattern is a clean, non-obvious SwiftUI technique
  worth preserving
- Code snippet: `AppError.swift` — the `unexpectedError` case and the
  distinction between network errors and truly unexpected failures shows
  the level of care in error messaging
- Diagram: data flow from `MenuBarLabel.onAppear` → `startPolling()` →
  `PollingService` → `fetchUsage()` → `UsageViewModel` → `MenuBarLabel` +
  `PopoverView` — shows the clean separation of concerns

**Story Thread**: This session belongs to "The Craft" arc — the point in
a project where the big decisions are made and what remains is the
discipline to do every small thing right. Every change here was in service
of one of three principles: visual consistency (pace dot parity, bar fill
color), cognitive load reduction (no competing color signal, settings
hidden), or production readiness (Sparkle, clean architecture, honest
error messages). None of them are dramatic. Together they make the
difference between a side project and a product.

---

## 2026-02-25 — v1.1: Shipped

**Phase**: The Build meets The Craft — from working prototype to production release

**What I Did**: Shipped Tokenomics v1.1 as a signed, notarized, publicly distributed macOS app with Sparkle auto-update support. The release is live at https://github.com/rob-stout/Tokenomics/releases/tag/v1.1. v1.0 users receive an in-app update prompt and can upgrade without visiting GitHub. The full pipeline — build, sign, notarize, DMG, sign DMG, notarize DMG, generate Sparkle appcast, publish GitHub Release — ran end-to-end in a single session.

**Why It Matters**: Shipping is a design decision. Many side projects reach "functional" and stop there. Publishing a notarized binary with a working update channel means accepting a higher bar: the app has to behave correctly on any user's machine, not just mine. That bar changes how you write error handling, how you structure settings, and what you consider "done." This release closes the gap between a prototype I can demo and a product I can point strangers to.

**Key Decisions**:

1. **Sparkle over manual GitHub releases as the update mechanism.** The alternative was telling users to re-download from GitHub. Sparkle puts the update in front of the user without requiring any deliberate action. The cost is one-time infrastructure: EdDSA key generation, appcast XML, a stable hosted URL. Once built, the cost of future releases drops to a single script invocation. The asymmetry — high setup cost, near-zero marginal cost per release — makes it the correct choice for any app expecting more than one version.

2. **`distribute.sh` as the release artifact.** The distribution pipeline has eight distinct stages with notarization polling between them. Manual execution invites mistakes. Encapsulating the full pipeline in a shell script makes the release process reproducible, auditable, and fast. It also means anyone who forks the project can ship from day one without re-learning the macOS notarization dance.

3. **Eliminated all force-unwrap crash risks before shipping.** The pre-release audit identified Swift force-unwraps that could crash on edge-case data. These were resolved before v1.1 went out. Publishing software with known crash vectors prioritizes developer convenience over user experience. Removing them was non-negotiable.

**What I Learned**: The macOS notarization process introduces a multi-minute wait you cannot shortcut. The `distribute.sh` script polls for notarization status automatically using `xcrun notarytool wait`, which makes the wait invisible. Small operational detail; meaningfully better release experience than manual re-checking.

Sparkle's appcast format is documented but its failure modes are not. Getting the `sparkle:edSignature`, `length`, and URL fields exactly right in the appcast XML required iteration. The working appcast is now in version control, which means the next release starts from a known-good template rather than from scratch.

**v1.1 Changes at a Glance**:

- Pace indicator dot on usage bars (visual parity with the menu bar rings)
- Animated bar fill on popover open, synchronized so both bars finish at the same moment
- Usage bars at white 50% opacity — better OS consistency than semantic grays
- Collapsible settings behind a gear icon (progressive disclosure)
- Inline About page explaining every UI element — a legend, not just credits
- Data loads on app launch, not on first click
- Keyboard shortcuts: Cmd+R (refresh), Cmd+Q (quit)
- VoiceOver accessibility labels on all interactive elements
- Sync timestamp updates in real-time while the popover is open
- Clearer error messages for network and authentication failures

**Artifacts to Capture**:
- Screenshot: the live GitHub Release page at v1.1 — the release itself as a portfolio artifact
- Screenshot: Sparkle update dialog as seen by a v1.0 user — proof the update channel works end-to-end
- Code snippet: `distribute.sh` — eight-stage pipeline in one script; demonstrates operational maturity alongside design and code skill
- Screenshot: popover in final shipped state — animated bars, pace dot, gear-collapsed settings — the visual baseline for any future iteration

**Story Thread**: This entry closes "The Build" arc and opens "The Reflection." The app is no longer a project — it is software. The release pipeline exists. The update channel is live. What follows will be driven by real feedback rather than assumed requirements. That shift — from building toward a spec to building in response to evidence — is where product thinking actually starts.

---
