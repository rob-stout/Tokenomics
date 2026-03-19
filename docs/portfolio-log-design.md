# Tokenomics — Portfolio Log (Design Lens)

Tokenomics is a macOS menu bar app that visualizes AI coding tool usage
as concentric rings, inspired by the Apple Watch Activity Rings. It polls
multiple AI provider APIs and renders rate-limit windows as live, animated
arcs directly in the menu bar.

This log retells the same milestones as the engineering portfolio log,
reframed through UX and UI lenses. Each entry foregrounds the design
problem, the user model, and the visual craft decisions — not the
technical implementation.

---

## 2026-02-25 — v1.1: The Concept Becomes a Product [UX+UI]

**Phase**: The Build — translating a design concept into a shippable, real-world tool

**The Problem**: I was building with Claude Code every day and had no idea
how close I was to hitting my token limits — until I hit them. The feedback
loop was broken. Limits reset at opaque intervals; the only signal was
an error in the terminal mid-session. I needed ambient awareness, not
reactive alerts.

**What I Built**: A macOS menu bar app that renders two concentric usage
rings — a 5-hour window (inner) and a 7-day window (outer) — directly
in the system menu bar. A pace dot on each ring shows where ideal even
usage would sit at this moment in the window. Click the icon to see a
popover with detailed bars, reset timers, and a percentage readout.

**UX Thinking**: The menu bar was the only right surface for this. It
is always visible, always on screen, zero interaction required to read it.
A notification would interrupt. A separate window would require context
switching. A badge on a Dock icon would be too easy to ignore. The rings
live exactly where peripheral vision already roams during a coding session.

The pace dot is the highest-value piece of the design. Percentage alone
tells you where you are; the pace dot tells you whether where you are is
fast or slow relative to how the window should ideally drain. A usage
bar at 40% fill with a pace dot at 60% is a red flag — you're burning
faster than the window can sustain. That insight is not available from
percentage alone.

**UI Craft**: The ring geometry was specified in Figma at 44px @2x and
implemented in CoreGraphics — pt coordinates, bitmap image rep, template
image mode so macOS handles light/dark adaptation automatically. Track
rings at 15% white opacity, fill arcs at 40–50% white opacity, round
line caps. The template image flag means I define the form; the system
applies the color. Menu bar icons that fight the system contrast model
are jarring; this one doesn't.

The popover uses vibrancy-backed material, which means fill colors need
to complement the blur rather than fight it. Four iterations on bar fill
opacity (0.9 → 0.7 → 0.6 → 0.5) landed on `Color.white.opacity(0.5)` —
the value that reads as a bar without feeling painted-on.

**Key Decision**: Removed color-shifting from the usage bars. The bars
changed from gray to orange to red as utilization climbed — the same
semantic logic as the rings. But the bars already communicate state
through fill amount. Two simultaneous signals (fill and hue) for one
variable (utilization) adds noise, not clarity. Cut the color. One visual
variable, unambiguous reading.

**What I Learned**: The gap between "functional prototype" and "shippable
product" is mostly a sequence of small design decisions, each of which
feels optional until you see them all together. Pace dots, animated bar
fills, the About view as a UI legend, settings behind a gear icon — none
of them are features. Together they define whether the app feels considered
or assembled.

**Artifacts to Capture**:
- Menu bar icon in multiple states: loading, live data, error, unauthenticated
- Popover in shipped state: animated bars, pace dot, collapsible settings
- About view with full UI legend (ring explanations, pace dot, plan badge)
- Before/after: settings exposed by default vs. collapsed behind gear icon
- CoreGraphics ring renderer — the geometry and alpha values that define the visual language

**Story Thread**: This closes "The Build" arc for v1.x. The concept — ambient
usage rings in the menu bar — was validated the moment I stopped missing my
token limits. The design work was making that concept feel like a native macOS
utility rather than a developer experiment.

---

## 2026-02-25 — Quality Pass: Design Consistency Before Adding More Features [UX+UI]

**Phase**: The Craft — polish, visual consistency, and production readiness

**The Problem**: The app worked. The design didn't cohere. Usage bars
and menu bar rings described the same concept (rate window utilization)
but used different visual vocabularies. Settings items of very different
types — a toggle, navigation rows, a destructive action — sat at the
same visual weight. The About view was a single undifferentiated block of
text that served two different user intents simultaneously.

**UX Thinking**: Conceptual consistency between surfaces is not aesthetic
preference — it is cognitive load reduction. When a user learns the pace
dot on the menu bar ring, they should immediately understand the pace
dot on the bar inside the popover. When those two elements look and behave
the same way, the mental model transfers for free. When they diverge, the
user has to re-learn the concept on each surface.

The pace dot was present on the rings but absent from the bars. That
inconsistency would confuse anyone who understood the ring metaphor and
then opened the panel. Adding the pace dot to the bars is not a visual
flourish — it is conceptual integrity.

The gear icon for settings follows progressive disclosure: settings are
secondary actions. Putting Launch at Login, Check for Updates, About, and
Quit at the same visual level as the usage data is a hierarchy failure.
The pattern used by Fantastical, Bartender, and iStat Menus — settings
behind a collapsible gear icon — is right because those apps have the
same primary/secondary split that Tokenomics has.

**UI Craft**: Bar animation on popover open: both bars animate from empty
to their live value over a fixed 0.5s ease-out, synchronized so they
finish at the same moment regardless of their individual values. The
synchronization required deliberately animating from 0 on `onAppear` and
resetting to 0 on `onDisappear`. A bar at 30% and a bar at 80% reaching
their final positions at the same time reads as a coordinated reveal; a
bar at 30% finishing in 0.2s and a bar at 80% finishing in 0.5s reads
as broken.

The About view as a UI legend — not credits, not marketing copy, but a
structured visual reference explaining every element in the app: outer
ring, inner ring, pace dots, plan badge, extra usage bar — gives new
users a path from confusion to clarity without burdening the main UI
with explanatory text. It replaces the main popover content inline,
preserving the popover geometry and corner rounding.

Polling moved to app launch, not first popover open. The rings should
be live before the user clicks the icon. An icon that shows empty rings
when first clicked asks the user to wait for the thing they're there to
read. That is a broken feedback loop on the smallest possible scale.

**Key Decision**: Architecture reflects design intent. The `UsageState.color`
property started in the model (`UsageData.swift`) and was moved to a view
extension (`UsageBarView.swift`). When model and view concerns are cleanly
separated, removing the color-shifting behavior later was a one-file change
with no ripple effects. The architectural decision enabled the design decision.

**What I Learned**: Every change here was in service of one of three
principles: visual consistency (pace dot parity, bar fill color), cognitive
load reduction (no competing color signal, settings hidden), or production
readiness. None are dramatic. Together they make the difference between
a side project and a product.

**Artifacts to Capture**:
- Pace dot on usage bars: before (absent) and after (present at pace position)
- Popover settings: before (exposed items) and after (gear icon collapsed)
- Animation: both bars reaching final value at the same moment
- About view as legend — the six UI elements explained with visual references

**Story Thread**: "The Craft" arc starts here. The big decisions are
already made. What remains is the discipline to do every small thing right.

---

## 2026-02-27 — Case Study Narrative: Making the Thinking Legible [UX]

**Phase**: The Reflection — structuring the project story for a hiring audience

**The Problem**: The code, the design decisions, and the iteration story
all existed in the codebase — scattered across source files, commit
messages, and log entries. None of it tells a coherent story to someone
who wasn't in the room. Building is one skill. Making the thinking behind
the build legible to someone reviewing a portfolio is a different skill,
and for job searching it is the more immediately useful one.

**UX Thinking**: The audience for a portfolio case study is not one
person — it is a design leader at one company, a startup founder at
another, a fellow designer at a third. Each needs a different entry point.
A design leader at Anthropic cares about the multi-provider strategic
thinking. A startup founder cares about the build-and-ship story.
A fellow designer cares about the craft decisions. Organizing the narrative
into five distinct angles — Builder Story, Craft Story, Technical Story,
Strategy Story, Iteration Story — lets each audience find what they need
without wading through the rest.

**Key Decision**: Organized the narrative around post-level angles, not
a single unified chronology. The source narrative contains everything;
the delivery angle is chosen per audience. One document serves all five
audiences by separating what happened from how it's framed for each reader.

**What I Learned**: The most compelling portfolio moments are not the
ones that went smoothly. They are the ones that reveal judgment under
constraint. The "Resets today" copy fix, the pace dot disappearing due
to negative elapsed time, and the self-healing OAuth retry are each small,
but each reveals a different dimension of how I think: copy precision,
mathematical edge-case analysis, infrastructure reasoning. A portfolio that
only shows polished outcomes doesn't show thinking. Showing what broke
and how I reasoned through it is more valuable.

**Artifacts to Capture**:
- `docs/case-study-narrative.md` — primary source for all downstream portfolio content
- The five LinkedIn post angles — each a discrete brief for a specific audience framing
- "Quotes Worth Pulling" section — exact lines from codebase and log usable verbatim in annotations

**Story Thread**: This closes "The Reflection" arc at the v1.x stage. The
project is documented. The thinking is preserved. The story can now be
told to people who weren't there — which is what a portfolio is for.

---

## 2026-03-03 — v2.2.0: Multi-Provider Expansion — Designing for Three Data Models at Once [UX+UI]

**Phase**: The Build — proving the multi-provider architecture with real users and real data

**The Problem**: Adding a second provider (Codex CLI) and a third
(Gemini CLI) sounds like a feature extension. It was actually a design
architecture test. The ring metaphor is self-evident for Claude — one
tool, two rate windows, two rings. Codex doesn't expose rate limits at all;
it exposes a context window. Gemini exposes request counts and token totals
with no meaningful reset timer. Three structurally different data models
feeding the same visual language: does the design hold?

**UX Thinking**: The `UsageProvider` protocol was the right abstraction
only if it could absorb genuinely different inputs without bending the
view layer. Three decisions tested that claim directly.

For Gemini, Google exposes no API to detect a user's plan tier — but
the limits differ by plan. Rather than blocking the provider or using
a hardcoded default, I designed a first-run inline flow: the
`GeminiPlanSetupView` appears inline the first time a user selects the
Gemini tab, replacing the usage content without a modal sheet. The provider
starts tracking immediately on a Free tier default; the user corrects it once
and never sees the flow again. The plan badge is tappable to reopen it.
Minimum friction for a setting most users configure once and ignore forever.

For Codex, the rate limit field in the JSONL session files is always 0.0 —
a confirmed CLI bug. The token count field, however, accurately reflects
context window fill, which is also the number the CLI shows in the terminal.
The design decision: show what is accurate and useful, not what is
technically labeled as a rate limit. The bar sublabel reads "230.7K of
258.4K remaining" — matching the CLI's own display, honest about what
is being measured.

For multi-provider display mode, the original design allowed pinning
multiple providers to the menu bar simultaneously. `MenuBarExtra` has a
hard width cap around 80–100pt. Two ring sets plus labels overflows it.
The fix replaced multi-pin with radio-button behavior: one provider pinned,
or Smart mode (worst-of-N utilization). Simpler mental model, same
decision power, fits the platform constraint.

**UI Craft**: The `sublabelOverride` field on `WindowUsage` solved
a concrete display problem without complicating the view layer. The original
model computed its own sublabel from reset timestamps. Gemini and Codex
have different information to show — request counts, token counts, no
reset time. Adding an optional `sublabelOverride: String?` field lets each
provider compute the right string without the view needing to know it
exists. Model layer owns the content; view layer owns the presentation.
Clean boundary.

Single-ring mode for providers with one meaningful metric (Codex's
context window): a single slightly thicker ring at the midpoint radius
between the two-ring positions fills the same visual space as the two-ring
variant. Users with only Codex installed see a ring that occupies the
same icon footprint. Providers with different data models look the same
from 18 inches away.

**Key Decision**: Display what's accurate and useful, not what's labeled
as a rate limit. The Codex decision specifically — showing context window
fill instead of the always-zero rate limit — is a design judgment. The
technically correct thing to do is show the documented field. The
user-correct thing to do is show the number that reflects their actual
constraint. These are not always the same. When they diverge, the user
wins.

**What I Learned**: The multi-provider expansion validated the design
architecture by stress-testing it with genuinely different inputs. An
abstraction that holds for one input is a coincidence. An abstraction
that holds for three structurally different inputs — API polling, JSONL
file parsing, JSON session file traversal — without the view layer
needing modification is a design principle.

**Artifacts to Capture**:
- Popover with all three provider tabs: Claude Code / Codex CLI / Gemini CLI
- GeminiPlanSetupView inline — plan selector with limit summary
- Codex tab: context window bar with "230.7K of 258.4K remaining" sublabel
- DisplayModeMenuView: Smart vs. pin options with checkmark/pin icon
- Data flow diagram: three providers → ProviderUsageSnapshot → PopoverView

**Story Thread**: This completes "The Build" arc at the multi-provider scale.
The strategy document described how this should work in theory. This release
shipped that theory as working, notarized, auto-updating software.

---

## 2026-03-04 — v2.2.2: Ring Language Redesign — Content Architecture as Design [UX]

**Phase**: The Craft — language as UX, and the problem of provider-agnostic copy

**The Problem**: With three providers, the ring metaphor that was
self-evident for Claude became genuinely ambiguous. The outer ring is the
7-day window for Claude, the model context window for Codex, and the daily
request cap for Gemini. Calling it the "7-day ring" in the About view is
accurate for one provider and wrong for two others. Copy that is
provider-specific fails multi-provider.

**UX Thinking**: The solution was not a per-provider lookup table in the
About view — a 320pt popover is the wrong surface for a table. It was
behavioral language that holds true regardless of provider: "nearest
limit" (inner ring) and "broader context" (outer ring). These descriptions
remain accurate whether the outer ring is a 7-day window, a context window,
or a daily cap. Provider-specific details follow as secondary reference for
users who want precision. The primary language is behavioral; the secondary
language is structural. Content architecture disguised as copy editing.

This is a UX writing problem, not a UI problem. The visual hierarchy —
inner ring, outer ring, pace dots — doesn't change. Only the words change,
and those words do the cognitive work of making an abstract metaphor
legible across different data models.

**Key Decision**: Behavioral labels ("nearest limit," "broader context")
over structural labels ("5-hour window," "7-day window"). Structural labels
require the user to remember which provider they're looking at and which
window maps to which ring. Behavioral labels require only that they
understand what the ring is telling them to do. One is a reference;
the other is a signal.

**What I Learned**: This entry reinforced that information architecture
decisions are not confined to navigation and screen structure. A two-word
label choice in a legend is an information architecture decision. The
question "what does this element need to communicate?" is always an IA
question, regardless of where it appears.

**Artifacts to Capture**:
- About view before (provider-specific language) and after (behavioral language)
- The specific copy: "nearest limit" / "broader context" — with annotation explaining why these terms hold for all three providers
- Legal section added to About view — privacy policy and license links

**Story Thread**: "The Craft" arc. A ring is still a ring; what changed is
the language that makes it legible to a user who might be tracking Gemini
today and Codex tomorrow.

---

## 2026-03-09 — Widgets, IA Redesign, and Rate Limit Defense — Three Design Problems, One Session [UX+UI]

**Phase**: The Craft — platform extension, information architecture, and graceful degradation as a design problem

**The Problem**: Three separate problems converged. First, the app's ambient
awareness concept was confined to the menu bar — a surface that disappears
when focus is elsewhere. Second, the About screen was trying to serve two
incompatible user intents on one surface. Third, Anthropic's OAuth endpoint
had a known bug that silently produced stale data — and the UI was
telling users it was failing rather than quietly handling it.

**UX Thinking — Widgets**: Widgets extend the ambient awareness concept
to the desktop surface users actually stare at between coding sessions.
The core design question was not "what should the widget show?" but
"what is the one number a developer needs at a glance?" For a
developer with multiple providers, the answer is the worst-of-N
utilization — the provider closest to its limit. That's the number
that requires action. Smart mode defaults to worst-of-N, making the
widget immediately useful after install with no configuration. Provider-
specific options exist for users who want to watch a single tool. The
default serves the 80%; the options serve the 20%.

**UX Thinking — IA Split**: The About view was simultaneously a legend
for confused users (what do the rings mean?) and a narrative for curious
users (what is this app?). Scanning for a specific answer and reading a
narrative are different cognitive modes. Combining them on one screen
means neither gets done well. The split was straightforward once the
two user intents were named: "How It Works" for the legend, "About
Tokenomics" for the identity narrative. The Desktop Widgets explainer
moved from Settings (wrong context — action rows, not explanatory text)
to How It Works (right context — conceptual explanations).

**UX Thinking — Rate Limit Defense**: The original stale data indicator
read "Rate limited · showing cached data." Accurate. Also alarming. It
implies failure and invites the user to question whether the data can
be trusted. The replacement — an orange-tinted "Updated Xm ago" in the
footer, tooltip available for detail — communicates the same information
without the negative frame. This is how weather apps, news feeds, and
dashboards handle stale data. The pattern exists because it has been
shown to work: it informs without alarming, gives the user a way to
assess data age, and implies the system is managing itself. Microcopy
that frames a failure as a state is always a design choice, and "Updated
Xm ago" is the right frame when the system is genuinely managing the
failure correctly.

**UI Craft**: The widget layout required a single-ring design for the
small widget (one ring, worst-of-N or specific provider). The ring is
rendered from the same `MenuBarRingsRenderer` used in the menu bar —
same CoreGraphics code, same geometry, scaled to widget dimensions.
Visual language is consistent across the menu bar, the small widget,
and the medium widget without maintaining separate implementations.

The medium widget needed a layout that handled variable provider counts.
The constraint: WidgetKit has no scrolling. The design response:
fixed-height rows that clip naturally at the visible area, with an
overflow indicator when count exceeds visible rows. Timer top-right in
the header, not displaced by overflow handling.

**Key Decision**: The three-layer OAuth defense (proactive token refresh
every ~22 hours, reactive refresh on 429, cached fallback with timestamp
microcopy) is an engineering solution in service of a design goal. The goal
was not to handle the 429 correctly — it was to make the API's instability
invisible to users who should not have to think about it. Graceful
degradation is a design principle with an engineering implementation.

**What I Learned**: Naming user intents before designing the screen is
a practice I apply in professional design work. It is easy to skip on
a personal project. The About screen problem existed for weeks before
the two intents were named explicitly. Once named, the solution was
obvious. The discipline of naming intent first applies to utility apps
exactly as it applies to enterprise products.

**Artifacts to Capture**:
- Small widget in macOS gallery: ring at worst-of-N utilization
- Medium widget: multi-provider dashboard with provider rows
- How It Works vs. About Tokenomics: side-by-side showing intent separation
- "Updated Xm ago" orange indicator vs. old "Rate limited" message
- Widget data flow diagram: App Group write/read contract

**Story Thread**: "The Build" and "The Craft" arcs intersect here. The
widget is new surface area; the IA split and microcopy decisions are pure
craft. The rate limit defense is engineering in service of design.

---

## 2026-03-09 — v2.2.6: Distribution as User Experience [UX]

**Phase**: The Build — treating the installation path as a first-touch design decision

**The Problem**: The target users for Tokenomics are developers. They
installed Claude Code from the command line. They manage their tools with
Homebrew. A DMG download is friction — five steps (find the release page,
click download, open DMG, drag to Applications, eject) where one
(`brew install --cask tokenomics`) is available and expected.

**UX Thinking**: Distribution is a UX decision. The moment of installation
is the first moment of the user experience. If that moment asks a developer
to leave their workflow, open a browser, navigate a GitHub release page,
and perform a drag-and-drop interaction they never do otherwise, you've
introduced friction before the app has delivered a single unit of value.
The Homebrew Cask meets the user in their environment, not yours.

Two channels, not one, because the two serve different use cases. The
direct download link matters for discoverability (GitHub search, web
search, landing pages — contexts where a terminal command is the wrong
answer). The Homebrew Cask matters for the moment of intentional
installation by the target user. One channel optimizes for reach;
the other optimizes for conversion with the right audience.

**Key Decision**: Treat the install command as a product decision with
the same rigor applied to onboarding flows and settings screens. The
reasoning — "who is the user and what is their workflow?" — is the same
question regardless of whether you're designing a first-run screen or
a release pipeline.

**What I Learned**: Distribution channels are not fungible. Each carries
its own trust signal and workflow affordances. A DMG on a GitHub release
page signals "this is a real macOS app from a developer who knows the
platform." A Homebrew Cask signals "this is a first-class developer tool
that someone cared enough to package for the ecosystem I already use."
Same binary. Two different trust signals. Two different adoption contexts.

**Artifacts to Capture**:
- The Homebrew Cask formula file — the shortest possible artifact that
  makes the decision concrete
- README showing both installation paths side-by-side — treats the
  install command as a first-class UX choice
- GitHub Release page with DMG asset — the two-channel strategy visible

**Story Thread**: "The Build" arc, specifically the part where building
means making software reachable. Most solo developer projects treat
distribution as an afterthought. Treating the install command as a
product decision is what distinguishes a developer tool from a developer
experiment.

---

## 2026-03-09 — Five Providers: Zero-Friction Auth as a Design Principle [UX]

**Phase**: The Build — expanding market coverage, maintaining the zero-friction principle

**The Problem**: Adding Copilot and Cursor to the provider list was
straightforward technically. The design question was harder: both tools
already have auth established on the user's machine (Copilot via the `gh`
CLI, Cursor via its local SQLite database). Do I ask users to authenticate
again specifically for Tokenomics, or do I lean on what's already there?

**UX Thinking**: The right design question is always "what has the user
already done that I can lean on?" not "what does my feature need?" A user
who has Copilot configured through the `gh` CLI has already done the
authentication work. Building a second login flow for Tokenomics is asking
them to do it twice. Copilot reads the existing `gh auth token` from the
system keyring — no additional configuration required. Cursor reads its JWT
from `state.vscdb` — the same file Cursor uses internally.

The install-and-forget experience is the reason a user doesn't uninstall
the app in the first ten minutes. Every extra setup step is attrition.
Zero-friction auth is not a feature; it is the condition that makes
all other features available.

**Key Decision**: Copilot was initially being built as a PAT entry flow.
I stopped and asked whether that was necessary. It wasn't. The `gh` CLI
token was already there. Building the second auth flow would have been
correct in a narrow technical sense and wrong in a user experience sense.

**What I Learned**: This iteration — start with the PAT flow, stop,
reconsider, implement the zero-friction path — is the pattern that
matters for a portfolio. It shows a design judgment overriding a
technical first instinct. That overrule is the job.

**Artifacts to Capture**:
- Popover with all five provider tabs: Claude Code, Codex, Gemini, Copilot, Cursor
- Onboarding view showing all five providers with connection state indicators
- Copilot tab and Cursor tab showing their respective usage bars
- `CopilotProvider.readToken()` and `CursorProvider.readAccessToken()` — the
  zero-friction auth pattern made concrete in code

**Story Thread**: "The Build" arc extended. Each provider is not just
a feature — it is a step toward a market position (engineering managers
wanting cross-tool visibility). This release reaches the threshold that
makes that position credible.

---

## 2026-03-09 — Provider Reorder and Visibility: Personalization at the Workflow Level [UX+UI]

**Phase**: The Craft — configurable surfaces, interaction design, and platform convention

**The Problem**: With five providers, the popover needed to be configurable.
A user who only uses Claude Code and Cursor shouldn't see three other tabs
taking cognitive space. The initial instinct — "remove provider" — creates
asymmetry: quick to hide, slow to restore. The interaction had to be reversible
and frictionless in both directions.

**UX Thinking**: The toggle model (eye visible, eye.slash hidden) is
reversible in a single tap from the same screen. It also means the provider
keeps polling in the background, which matters: when a user re-enables a
tab, they see current data immediately. If background polling stopped when
a provider was hidden, re-enabling it would show a stale timestamp — a
worse experience than fresh data on reveal. The design and the polling
behavior are coupled decisions.

Tab reordering went through three design iterations:

1. SwiftUI's `.onDrag` / `.onDrop` — the standard API, which fails in
   floating popovers because SwiftUI's drop target detection doesn't fire
   correctly inside a floating panel.
2. Arrow buttons (left/right) on each tab — technically functional,
   visually noisy, slow for reordering more than one item.
3. `DragGesture` gated on `NSEvent.modifierFlags.contains(.command)` —
   Cmd+drag, matching the muscle memory macOS developers already have
   for reordering menu bar items.

The Cmd modifier gate is the key insight. It distinguishes a reorder
intent from a scroll or swipe, and it matches the platform convention
that makes the gesture learnable without a tutorial.

**UI Craft**: Five provider tabs at 320pt required either extremely compact
labels or a scrolling tab bar — both of which hurt scannability. Testing
with all five providers visible made the problem obvious. At 360pt, five
short labels (Claude, Codex, Gemini, Copilot, Cursor) fit comfortably with
confident tap targets. This is layout math validated through observation,
not calculated ahead of time.

The eye/eye.slash toggle uses SF Symbol conventions — filled for active
state, outline for inactive — which communicates state without additional
label text. The pattern is legible to any user who has used macOS recently.

**Key Decision**: Cmd+drag over arrow buttons because the former matches
existing platform muscle memory and the latter requires learning a new
affordance. Platform conventions are not constraints on creativity — they
are creative work already done by the platform that the user has already
internalized.

**What I Learned**: SwiftUI's drag-and-drop APIs are built for list views
and document-model apps. Using them in a floating popover produces behavior
that technically works but doesn't feel right. Reaching for `DragGesture`
with a manual modifier check was more implementation work but produced
behavior that feels native. Feeling right and working are different bars.
For interaction design, feeling right is the higher bar.

**Artifacts to Capture**:
- AI Connections view with eye/eye.slash controls and Cmd+drag hint text
- Popover at 320pt (crowded, five tabs) vs. 360pt (comfortable) — the width rationale made visible
- `ProviderTabView` drag gesture — the Cmd modifier gate that makes the gesture learnable

**Story Thread**: "The Craft" arc, specifically the part where craft means
making a technically functional feature feel right rather than just work.
The three-iteration path to Cmd+drag is a clean example of how design
decisions that look simple from the outside required multiple failed
attempts to land correctly.

---

## 2026-03-09 — Settings Redesign: Information Architecture Scales Before the Screen Does [UX+UI]

**Phase**: The Craft — information architecture, visual hierarchy, and designing for future growth

**The Problem**: Flat lists scale poorly. At eight items, the Settings view
was already showing strain — a toggle, navigation rows, a destructive action,
and informational links sitting at the same visual weight with no grouping
signal. A ninth or tenth item doesn't create a discrete problem; it makes
the existing problem continuously worse. Fixing it before it became
obviously broken was the right time.

**UX Thinking**: The mental model question for any settings list: "Can a
user predict where a given item lives before they start scanning?" A flat
list produces no such prediction — every item requires inspection. Grouped
sections with labeled headers give users a cognitive frame before they read
a single label. "Preferences" means behavioral. "Learn" means informational.
The frame reduces the scan from N items to whichever section is relevant.

I produced four HTML mockups (Options A–D) before committing to implementation:
- A: section labels — chosen as final design
- B: icon-only differentiation, no section headers
- C: grouped by frequency of use
- D: destructive actions in a separate zone

This is a practice I apply in professional design work. Generating
alternatives, even for a utility settings screen, forces articulation of
what you're optimizing for. Option A was always going to win, but having
Options B, C, and D makes the reasoning behind it explicit rather than
implicit. If someone asks in six months why the settings are organized this
way, there's a documented answer.

**UI Craft**: SF Symbol icons on every row serve three functions.
First, visual scanning: they give the eye anchor points in an all-text
list, reducing cognitive load per row. Second, structural signaling: the
icon + label + trailing control pattern signals "navigable row" vs.
"toggle" before the user reads the label. Third, platform alignment:
this is the same pattern used by macOS System Settings and iOS Settings.
Users arrive with existing muscle memory.

The section labels use uppercase text at 10pt with 0.8pt tracking —
the same visual treatment used by macOS system UI for section headers.
Not styled to be distinctive; styled to match the platform's own
organizational vocabulary.

The footer condensed to two inline elements (Check for Updates, Quit with
version number in line) rather than three rows. Secondary app-level
commands — not settings, not navigation — belong below the list with
reduced visual weight.

**Key Decision**: Option A over C (frequency-based grouping) because
"which items does this user access most?" varies by user and requires
predicting behavior I don't have data for. Frequency-based grouping
optimizes for a persona; section-based grouping optimizes for a task
structure that is stable across personas. Stable structures are more
durable than optimized ones.

**What I Learned**: The four-option process at small scale revealed
the same thing it reveals at large scale: the act of generating
alternatives is what surfaces the criteria for choice. Without options
B, C, and D, the reasoning behind Option A is implicit. With them,
it is documented. Process artifacts are portfolio artifacts.

**Artifacts to Capture**:
- Settings view: flat eight-item list (before) vs. two-section grouped layout (after)
- The four HTML mockup files A–D — process artifact showing deliberate exploration
- Section label and nav row code helpers — the reusable patterns that make the layout extensible

**Story Thread**: "The Craft" arc. Settings is the least glamorous surface
in any utility app and the one that most clearly reveals whether the
designer thinks about structure or just content. Grouped sections with
labeled headers is a solution to a scaling problem, not a visual preference.

---

## 2026-03-09 — Signing Fix: When Platform Constraints Are Invisible Until They're Not [UX]

**Phase**: The Build — platform constraints and silent failure modes as user experience problems

**The Problem**: Widgets were not showing updated data. The app was
writing. The widget was reading. Both were succeeding. The data was wrong.
No error. No log output. The symptom — a widget showing stale zero data —
looked like a display bug or a polling bug. It was neither.

**UX Thinking**: Silent failure modes are a design problem before they
are an engineering problem. When a feature fails silently — no error,
no indication, plausible-looking wrong data — users don't know to report
it. They assume the feature doesn't work, or that they're doing something
wrong, or that the app is simply broken. The user experience of zero
data in a widget is identical whether the cause is a network failure,
a code bug, or a signing mismatch. The user sees the same thing.

The root cause: the main app (non-sandboxed, team A) and the widget
extension (sandboxed, team B) both claimed the same App Group identifier,
but macOS resolved the container path differently for each team. The
feature that was tested during development was not the feature that
shipped, because the team ID used in testing was not the team ID used
in release. Aligning both configurations on the program team meant debug
and release builds behave identically with respect to entitlements.

**Key Decision**: The fix was not a special-case path for widgets —
it was standardizing both configurations on the same team ID, so the
behavior tested during development is the behavior that ships. Any
feature involving inter-process communication requires that both the
debug and release configurations use the same identity. Testing one and
shipping the other is not testing the feature at all.

**What I Learned**: The category of bug here is "correct configuration,
wrong scope." Every individual piece was configured correctly. The error
was assuming a debug-only configuration difference could be isolated
from a cross-process data-sharing feature. Assumptions about configuration
isolation are the same class of assumption as assumptions about user
behavior: they feel safe until they aren't.

**Artifacts to Capture**:
- `project.yml` snippet showing both debug and release using the same team
- Description of the symptom vs. root cause — the debugging process
  narrative, not just the fix

**Story Thread**: "The Build" arc, specifically the category of platform
constraints that are invisible at every layer except the one that matters:
the user's widget showing the wrong numbers.

---

## 2026-03-12 — v2.5.0: Widget Layout System — Designing for Constraint [UX+UI]

**Phase**: The Craft — responsive layout design under hard platform constraints, validated through explicit state testing

**The Problem**: WidgetKit is a constrained surface: no scrolling, fixed
dimensions, tap interactions limited to URL schemes. A layout that handles
three providers well and falls apart at one or seven is not a design system;
it is a design for the average case. The widget needed to work at every
provider count from one to eight-plus — with the same visual language,
without crowding, without empty space becoming dead space.

**UX Thinking**: The most revealing moment in this session was a layout
decision framed as an overflow strategy. The proposed solution to the medium
widget hitting its provider cap was to replace the countdown timer with a
"+X in app" indicator. I pushed back: the timer is one of the most useful
pieces of information in the widget, and hiding it punishes users who have
more providers configured. This is a trade-off between layout convenience
and user information loss, and the user wins. We iterated through three
options before landing on a centered footer below the provider list — the
timer stays in the header, the overflow indicator lives below the content
it describes, no user loses information they were relying on.

The three layout tiers for the large widget — spacious (1–4 providers),
compact two-column (5–7), compact two-column with overflow footer (8+) —
came from testing each provider count explicitly. My initial compact
threshold was 4+ providers. Testing showed four providers still fit
comfortably in the spacious single-column layout. The threshold moved
to 5+. The final tier structure came from evidence, not extrapolation.

**UI Craft**: The Share CTA solved the empty-space problem with function.
Low provider counts (1–2 on medium, 5–6 on large) leave visible dead
space at the bottom of the widget. Rather than leaving it blank or
filling it with tips, I used it for gentle organic growth: an SF Symbol
`square.and.arrow.up` + "Tokenomics" text at 40% opacity. Subtle enough
not to feel like advertising. Functional enough to justify its presence.
Implemented via a `tokenomics://share` deep link — the only way to
trigger code from a widget tap is a URL scheme.

The 8px grid decision is the smallest moment that illustrates the largest
principle. When the "Requests" label was clipping, I proposed 52px as
a fix. The correct response: 4px of additional space is all that's needed,
and 48px keeps the value on the 8px grid. The grid is not decoration.
It is a discipline that prevents accumulated visual drift across a component
library. Maintaining it under pressure is how a visual system stays coherent.

HTML mocking as the primary design environment for all nine widget states —
every relevant provider count across medium and large — before any Swift
was written. Slider controls in the HTML let me dial in gap values in
real time. Layout decisions that would take 10–15 minutes per iteration
in Xcode took 30 seconds in a browser. The feedback loop drives the quality
of the outcome.

The header bottom padding (20px) being larger than the inter-provider gap
(16–24px depending on tier) is a visual grouping technique: providers
cluster together and away from the header, which reads as a unit. "The
providers should group visually" is easier to articulate than to specify
numerically. The HTML mock made it possible to feel the right value rather
than calculate it.

**Key Decision**: The timer stays. When a layout problem and a user
information loss are in conflict, user information wins. Layout problems
have alternative solutions; information that's removed is information
that's gone.

**What I Learned**: WidgetKit's tap model — `widgetURL` for the whole
widget, `Link(destination:)` for a specific zone — creates a clean
priority hierarchy. The Share CTA wraps its content in a `Link`, which
takes precedence over the `widgetURL` tap target in its zone only. A
tappable sub-region without restructuring the entire tap architecture.
Non-obvious until you test it.

**Artifacts to Capture**:
- HTML mock file — nine states, all provider counts for medium and large;
  the design process, not just the outcome
- Medium widget at 1, 2, 3, and 4+ providers — layout tier transitions
- Large widget at 4, 5, 7, and 8+ providers — three-tier system and overflow footer
- Share CTA in context — 40% opacity treatment at low provider count
- Before/after: medium widget at 4 providers before overflow cap (crowded) vs. after (3 visible + footer)
- Widget tap architecture diagram: `widgetURL` vs. `Link(destination:)` priority

**Story Thread**: Firmly in "The Craft" arc. Every significant decision
here came from pushing back on a first-pass solution. The timer survived
because I wouldn't trade user information for layout tidiness. The 8px
grid held because visual systems only work if you maintain them under
pressure. The share CTA exists because empty space is a product decision,
not a layout failure.

---

## 2026-03-17 — Connections Page Redesign: Designing the Model Before the UI [UX+UI]

**Phase**: The Approach — product strategy and information architecture for an expanding provider landscape

**The Problem**: Tokenomics was ready to expand into creative AI tools —
image generation, video, music and audio. That expansion exposed a
structural problem in the existing Connections page: a flat provider list
assumes one connection equals one tool. It doesn't anymore. OpenAI's
billing pool covers Codex CLI, DALL-E, and Sora under one API key.
Google AI's covers Gemini CLI, Nano Banana 2, and Veo. A flat list with
individual toggles for each service presents a false affordance: toggling
DALL-E off without touching Codex is not an action the user can actually
take when they share credentials.

**UX Thinking**: The mistake most products make with expanding scope is
retrofitting the UI to fit new content rather than redesigning the model
to fit new reality. Adding creative AI providers to the flat list would
have shipped controls that don't match the underlying system — confusing
at best, misleading at worst.

The most tempting design was an accordion: an OpenAI row that expands
to reveal Codex, DALL-E, and Sora as sub-items, each with its own toggle.
This is a false affordance. You cannot connect to DALL-E without also
connecting to Codex — they are the same OAuth credential. A sub-toggle
implies independent control that doesn't exist. The correct model is one
ecosystem entry with a subtitle listing included services ("Codex CLI ·
DALL-E · Sora"). One connection, one toggle, transparent about what
it covers.

Section-based organization does more than organize the screen — it teaches
the AI tool landscape. Grouping providers into Platforms, Coding Tools,
Image Generation, Video Generation, and Music / Audio / Voice shows users
that the AI tool landscape has structure. A developer who has only used
Claude Code and Copilot may not know that the same API key powering
text generation also covers image and video credits. The section model
surfaces that structure implicitly.

Settings sections are fixed; popover stays flat. Settings is discovery
and management: users need to understand what's available and how it's
organized. The popover is workflow: users need fast access to the
providers they've already configured. Imposing category sections on the
popover would add cognitive overhead to the task where friction matters
most. Same information, different surfaces, different structures — each
optimized for the job it's doing.

The three-state provider model (Not Connected → Connected+Visible →
Connected+Hidden+Disconnect) handles the multi-provider case that the
original binary model couldn't. A user might want to connect to Google AI
for tracking but hide it from the popover while usage is low. Progressive
disclosure: the destructive action (Disconnect) only appears when the
provider is already hidden, reducing accidental disconnection risk while
keeping the action reachable.

**UI Craft**: The ecosystem subtitle pattern ("Codex CLI · DALL-E · Sora")
is the key visual proof of the "one toggle per ecosystem" decision. It
answers the user's question "what am I connecting to?" without requiring
them to already know the billing structure. The subtitle does the teaching
work that a flat list cannot.

Provider icons for Codex and Gemini already used the OpenAI and Google AI
logos — a decision made when the icons were designed, before the ecosystem
rename was considered. Renaming Codex CLI to OpenAI and Gemini CLI to
Google AI is therefore a label change only. No icon assets need updating.
The icons were right before the names caught up. This is the kind of
small consistency that only becomes visible when you look at the whole
system together.

**Key Decision**: Design the correct model before writing the first line
of integration code. Identifying that the flat list was wrong before
shipping the first creative provider required looking one step ahead of
the current feature. Discovering the billing pool problem during
integration — mid-feature-development — would have been the most
expensive time to do the settings page redesign.

**What I Learned**: The core tension in this redesign was organizational
clarity vs. workflow speed. Section labels in Settings help users understand
the landscape; sections in the popover would slow down the repeated daily
interaction. The insight was that "understand what's available" and "access
what I use" belong on different surfaces. Settings is the map; the popover
is the route. Solving both on the same screen would have meant compromising
both. Separating them let each surface be unambiguously optimized.

**Artifacts to Capture**:
- `mocks/connections-mockup.html` — the primary design artifact; all three
  provider states, section organization, ecosystem/shared-pool treatment
- Annotated screenshot of Platforms section — "Codex CLI · DALL-E · Sora"
  subtitle pattern; visual proof of the "one toggle per ecosystem" decision
- Three-state diagram: Not Connected → Connected+Visible → Connected+Hidden+Disconnect
- Provider landscape map: coding tools vs. creative providers, with billing
  pool groupings marked — the strategic artifact that motivated the redesign

**Story Thread**: "The Approach" arc. The right question was not "what
should the UI look like?" but "what model does the UI need to reflect?"
The Connections page redesign is a conceptual architecture problem wearing
a UI hat. Designing the correct model before writing the first integration
line is the decision that only looks obvious in hindsight.

---
