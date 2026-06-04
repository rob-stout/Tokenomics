# Onboarding Usage-Triage Step — Design Spec

**Status:** Proposal for review (Rob to decide open questions at end)
**Author:** Design
**Scope:** New onboarding step that asks *how* a user accesses AI before asking *which* brands they use, to shrink the brand multi-select.
**Implementation note:** This is a design spec. No Swift was written. New vs. reused components are flagged in §7.

---

## 0. Source-of-truth citations

Visual decisions below are grounded in the live token + component source, not guessed:

- **Tokens (color/spacing/radius/type/motion):** `Tokenomics/Views/DesignSystem/Tokens.swift`
  - Spacing 8pt grid: `Tokens.Spacing` (s2=8, s3=12, s4=16, s5=24, s6=32) — lines 156–166
  - Radius: `Tokens.Radius` (sm=10, md=14, pill=999) — lines 170–177
  - Onboarding type: `Tokens.Typography.Onboarding` (h2=DM Sans 22 semibold, lede=15, body=14, small=13, micro=11 medium) — lines 198–225
  - Theme colors: `Tokens.Color.{text,textMuted,textSubtle,surface,border,borderStrong,accent,accentInk}(scheme)` — lines 93–117
  - Motion: `Tokens.Motion.ease` (0.22s timing curve) — lines 261–268
- **Window chrome / winbody padding:** `ConnectorContainer.swift` lines 78–88 — every synthesis step uses `.padding(.top, s6=32)`, `.padding(.horizontal, 40)`, `.padding(.bottom, s5+4=28)`. Window is 720×560 (mockup `.window` `guided-onboarding-mockup.html` lines 192–201). *(Note: the MEMORY note "680×580" is stale; the live code and mockup are 720×560 — I matched the code.)*
- **Footer:** `Components/WindowFooter.swift` + `BackLink` — divider + leading/trailing slots, padding-top s5.
- **Row group pattern (card with hairline-divided rows, checkbox, sub-label):** `Steps/MultiSelectStep.swift` lines 140–234.
- **Button styles:** `DesignSystem/TokenButtonStyle.swift` — `.tokenPrimary`, `.tokenTextLink`.
- **Brand → pool map (the crux):** `Models/Provider.swift` `BrandId.pools` lines 333–348; web-companion classification mirrors `PlanBuilder.isWebCompanionOnly` lines 262–269 and `cliBrands` line 26.

---

## 1. Where it slots in the flow

### Current flow
```
welcome → permissions → multiSelect → setupPlan → (chooser → connector)
                              │
                              └─ detection runs here (.task), pre-checks rows
```

### Proposed flow
```
welcome → permissions → usageTriage → multiSelect → setupPlan → (chooser → connector)
                              │             │
              detection runs here ──────────┘ (move detection earlier; see below)
              (triage can also pre-select methods from detection signals)
```

**Why between `permissions` and `multiSelect`:**

1. **It is a funnel, not a fork.** Triage's only job is to *narrow* what `multiSelect` renders. It must run immediately before the screen it filters so the user perceives cause→effect ("I said Browser, so I only see browser tools"). Putting it before `permissions` would break that adjacency and front-load an abstract question before the user understands the app's purpose.

2. **It does not replace `welcome` or `permissions`.** Welcome sets the value prop and emotional frame; permissions is a hard macOS gate that must happen regardless of access method. Triage is additive and cheap — one tap or two.

3. **Detection should move from `multiSelect`'s `.task` to run during/after `permissions`** (it already needs keychain access granted in `permissions` to read some signals). Detection results then do double duty:
   - **Pre-select triage methods** (see §5 "not sure" + smart defaults): a `.cliCredentials` signal → pre-check CLI; a `.nativeApp` (Claude.app, ChatGPT.app) → pre-check Desktop; a `.bridgeConnected` signal → pre-check Browser.
   - Continue to pre-check brand rows in `multiSelect` exactly as today.

   This is a behavioral win: the most common returning/power user lands on triage with the right methods already lit, turning a question into a *confirmation* (recognition over recall, lower cognitive load).

**Net change to `multiSelect`:** it receives a new input — the set of selected access methods — and filters its `groups` accordingly (§3). Everything downstream (`SetupPlanStep`, `PlanBuilder`, the execution queue) is unchanged because triage never alters pools; it only controls which brand rows are *visible to select*.

---

## 2. The screen design

### Layout sketch (720×560, winbody 32/40/28)

```
┌──────────────────────────────────────────────────────────────┐  ← titlebar (existing chrome)
│                                                                │
│  How do you use AI?                          ← h2 (DM Sans 22) │
│  Pick all that apply — this trims the next                     │
│  list to just what's relevant to you.        ← lede (15, muted)│
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │  ← one card (surface, border, r-sm)
│  │ ☑  🌐  In a browser                                    │    │     rows divided by hairline
│  │        Claude, ChatGPT, Gemini, Midjourney on the web  │    │     (matches MultiSelectStep
│  │ ──────────────────────────────────────────────────    │    │      categorySection pattern)
│  │ ☐  🖥  In a desktop app                                 │    │
│  │        The Claude or ChatGPT app on your Mac           │    │
│  │ ──────────────────────────────────────────────────    │    │
│  │ ☐  ⌨️  In the terminal / an IDE                         │    │
│  │        Claude Code, Codex, Gemini CLI, Cursor, Copilot │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                │
│  Not sure? Skip this — we'll show everything. ← textLink (acc) │
│                                                                │
│  ──────────────────────────────────────────────────────────  │  ← WindowFooter divider
│  ← Back                                  Continue  → (primary) │
└──────────────────────────────────────────────────────────────┘
```

### Component anatomy

- **Header block** — identical structure to `MultiSelectStep` (lines 89–100): `VStack(alignment:.leading, spacing: s2)` with h2 title + lede subtitle, `.padding(.bottom, s5)`.
- **The selection control** — a **single card** (`surface` fill, `border` 1px stroke, `Radius.sm`=10) containing **three checkbox rows** divided by hairline `Rectangle().fill(border)` inset to align under the label. This is a verbatim reuse of `MultiSelectStep.categorySection` + `rowView` (lines 140–203). Each row:
  - 18×18 checkbox (reuse `MultiSelectStep.checkbox`, lines 218–234 — accent fill + checkmark when on).
  - Leading 22pt SF Symbol glyph (see icon choices in §4) in `accent` color, matching the icon+text rhythm of `PermissionsStep.permissionCard` (lines 141–146).
  - Label: `Onboarding.body` (14). Helper sub-text: DM Sans 12, `textSubtle` (matches MultiSelect sub-label, line 191).
  - Row padding: `.vertical s3` / `.horizontal s4` (MultiSelect line 198–199). Whole row is one tap target → comfortably > 44pt tall.
- **"Not sure" escape** — `.tokenTextLink` button (accent), placed *above* the footer divider so it reads as content, not a footer action. Spacing `s5` above the footer.
- **Footer** — `WindowFooter { BackLink(action: onBack) } trailing: { Continue }`. Continue uses `.tokenPrimary` with the trailing `arrow.right` glyph, matching `MultiSelectStep` (lines 120–128) and `SetupPlanStep` (lines 54–61).

### Why a checkbox card, not a segmented pill or big tiles

- The mockup's **segmented pill** (`.plan-tabs`, HTML lines 792–818) is single-select and used for plan tiers — wrong semantics for a multi-select. Reusing it would teach the wrong mental model.
- **Big icon tiles** (3-up grid) photograph well but cost more vertical space, need their own selected-state styling (new component), and read as single-select to most users. The checkbox card reuses an existing, tested pattern and unambiguously signals multi-select. Restraint over novelty (UI skill §5).

### States

| State | Treatment |
|---|---|
| **Nothing selected** | Continue **enabled** (skip semantics — see §5). The "Not sure" link is redundant-but-harmless; both routes show the full list. |
| **One selected** | Standard. Continue enabled. |
| **Multiple selected** | Standard. Continue enabled. |
| **All three selected** | Equivalent to today's full `multiSelect` (§5). |
| **Pre-selected from detection** | Relevant rows arrive checked with no extra annotation needed (keep it clean — the *why* surfaces later as brand-row sub-labels in `multiSelect`). |
| **Hover (row)** | No dedicated hover fill required; checkbox + cursor is enough, consistent with `MultiSelectStep` rows which also have no row-hover. |

### Dark mode

Inherits automatically — every color is a `Tokens.Color.*(scheme)` accessor (accent flips brand600→brand200, surfaces flip cream→ink). No bespoke dark values. This matches how `MultiSelectStep` and `PermissionsStep` already behave.

### Motion

Row check toggle is instant (state change). If the team wants polish, animate the downstream `multiSelect` list trimming with `Tokens.Motion.ease` (0.22s) so the user *sees* their triage choice shrink the next list — but that lives on the `multiSelect` screen, not here. No motion required on triage itself.

---

## 3. How it reduces downstream complexity (the mapping)

Triage selects a set of **access methods**. `multiSelect` shows a brand row **iff at least one of its pools is reachable by at least one selected method.** Triage never changes pools — it only gates row *visibility*.

### Method → ProviderId membership

Derived from `BrandId.pools` and `PlanBuilder` classification (`isWebCompanionOnly` line 262, `cliBrands` line 26):

| Method | Pools (ProviderId) it surfaces | Brands those pools belong to |
|---|---|---|
| **Browser** | `.chatgpt`, `.geminiConsumer`, `.midjourney` (+ `.claude` via claude.ai bridge, `.suno`/`.udio` when live) | Claude, ChatGPT, Gemini, Midjourney |
| **Desktop app** | desktop-app usage of `.claude`, `.chatgpt` | Claude, ChatGPT |
| **CLI / terminal** | `.claude` (Claude Code), `.codex`, `.gemini`, `.cursor`, `.copilot` | Claude, OpenAI, Google, Cursor, Copilot |

> **Important modeling note for the developer:** Anthropic is *unified* — `.claude` is one pool covering chat + desktop + Code (`BrandId.pools` line 334 comment in `Provider.swift`). So "Claude" qualifies under **all three** methods. ChatGPT spans Browser/Desktop (`.chatgpt`) **and** CLI (`.codex`). Gemini spans Browser (`.geminiConsumer`) and CLI (`.gemini`). The mapping above already accounts for this — a brand appears if *any* selected method touches *any* of its pools.

### Resulting visible brand rows in `multiSelect`, by selection

`multiSelect` currently groups rows as: multi-purpose (Claude, ChatGPT, Gemini), code (Copilot, Cursor), media (Stability, Midjourney, Runway, ElevenLabs) — see `MultiSelectStep.groups` lines 67–85.

| Triage selection | Brand rows shown | Effect |
|---|---|---|
| **Browser only** | Claude, ChatGPT, Gemini, Midjourney | Hides Copilot, Cursor, Stability/Runway/ElevenLabs and the whole "code" category. No terminal-flavored steps downstream. |
| **Desktop only** | Claude, ChatGPT | Tightest list. (Gemini has no desktop pool, so it drops.) |
| **CLI only** | Claude, ChatGPT, Gemini, Copilot, Cursor | Hides web-only Midjourney + the API-key media tools. |
| **Browser + CLI** | Claude, ChatGPT, Gemini, Copilot, Cursor, Midjourney | Union — no double rows (brand appears once even though both methods touch it). |
| **All three** | Full current list | Identical to today (§5). |
| **None / "Not sure"** | Full current list | Identical to today (§5). |

### Overlap handling (no double-asking)

The brand multi-select stays **brand-level**, exactly as today. A brand shows **once** regardless of how many selected methods touch it. The user checks "Claude" one time; `PlanBuilder` already resolves Claude → `[.claude]` and the execution queue already batches web-companion pools into one extension step (`ConnectorContainer.buildExecutionQueue` lines 251–273). **Triage requires zero changes to `PlanBuilder` or the queue** — it is purely a visibility filter on rows.

### What about the media/API-key tools (Stability, Runway, ElevenLabs)?

These aren't "browser / desktop / CLI" tools — they're API-key services. Two options (see Open Questions §6): (a) always show them in `multiSelect` regardless of triage (they're a separate "connect with a key" lane), or (b) gate them behind a 4th implicit bucket. Recommended: **always show the media category**, because triage is about *coding/chat access surface*, and API-key media tools don't fit that axis. Hiding them based on triage would make them undiscoverable. This keeps triage honest: it filters the brands that genuinely have a browser/desktop/CLI distinction.

---

## 4. Copy

**Headline (h2):**
> How do you use AI?

**Lede (15, muted):**
> Pick all that apply — this trims the next list to just what's relevant to you.

**Option rows** (label = `Onboarding.body`; helper = DM Sans 12, `textSubtle`):

| Icon (SF Symbol) | Label | Helper text |
|---|---|---|
| `globe` | **In a browser** | Claude, ChatGPT, Gemini, or Midjourney on the web |
| `macwindow` | **In a desktop app** | The Claude or ChatGPT app on your Mac |
| `terminal` | **In the terminal or an IDE** | Claude Code, Codex, Gemini CLI, Cursor, Copilot |

**Escape link (textLink, accent):**
> Not sure? Skip — we'll show everything.

**Footer CTA:** `Continue →` (primary)

**Tone rationale:** plain, second-person, names the *payoff* of answering ("trims the next list") rather than the mechanic. Helper text uses real product names users recognize so they self-select by recognition, not by parsing an abstract category (recognition over recall). Avoids jargon like "access method."

---

## 5. Edge cases

1. **User selects nothing → Continue.** Continue stays **enabled**; an empty triage selection is treated identically to "show everything" (full current `multiSelect`). Rationale: triage is an *optimization*, never a gate. Forcing a selection adds friction with no user benefit and risks a confused user bouncing. (Contrast: `MultiSelectStep` *does* disable Continue when empty, because there you must pick at least one brand to track — different semantics, intentionally.)

2. **"Not sure" / Skip link.** Present as a `textLink`. Same outcome as empty-Continue, but gives an explicit, low-anxiety out for users who don't want to think about it. Two paths to the same safe default is fine — it serves two emotional states (the decisive skipper and the uncertain one).

3. **Selects all three.** Collapses to today's exact full list — no special-casing, the union of all methods *is* the full set. Verified against the mapping table in §3.

4. **Detection pre-selects methods, user changes mind.** Once detection seeds the triage checkboxes, the user can uncheck freely. Mirror the `runDetection` guard in `ConnectorContainer` (lines 164–181): only seed on *first* entry; if the user taps Back from `multiSelect` and returns, preserve their triage edits (don't re-seed). New `@State var triageSelection: Set<AccessMethod>` should follow the same "seed once" rule as `draftSelection`.

5. **Triage filters out a brand the user actually wanted.** Because triage only hides rows in the *batched* `multiSelect`, the existing **"Or set them up one at a time"** escape (`MultiSelectStep` line 130 → `chooser`) must show the **full** unfiltered provider list. The chooser is the safety net: nothing is permanently hidden, the user is one tap from everything. This is the critical forgiveness path — do not let triage leak into the chooser's list.

6. **Back from triage.** Routes to `permissions` (`onBack`), consistent with the chain. No state lost.

---

## 6. Open questions / tradeoffs for Rob

1. **Media/API-key tools visibility (§3 tail).** Recommend always-show. Alternative: add a subtle 4th option ("With an API key — Stability, Runway, ElevenLabs"). That makes triage exhaustive and self-documenting, but adds a row that ~most users won't relate to and muddies the clean 3-way mental model. **Your call: clean 3-option triage + always-show media, or exhaustive 4-option triage?**

2. **Is "Desktop app" worth its own option?** It only ever yields Claude + ChatGPT, and Claude is unified (so the desktop pool is indistinguishable from chat/CLI for tracking). The honest version is that "Desktop" barely narrows anything beyond "Browser." Options: (a) keep three for conceptual completeness; (b) collapse to **two** options — "On the web / in an app" vs. "In the terminal / IDE" — which is the cleaner real split given our actual tracking. **I lean toward (b) two options** unless you want the desktop signal for analytics/copy reasons. This is the biggest decision.

3. **Window size discrepancy.** MEMORY says 680×580; live code + mockup say 720×560. I designed to the code. Confirm which is current so the doc cites the right number.

4. **Detection-driven pre-selection of methods.** Powerful but adds coupling (triage now depends on detection finishing). If detection is slow/unavailable, triage should render with nothing pre-checked and still work. Confirm you want the pre-select behavior, or prefer triage start blank for predictability.

5. **Does triage's selection persist anywhere**, or is it ephemeral (only used to filter this session's `multiSelect`)? Recommend ephemeral — it's a UI funnel, not user data. But if you later want "I use AI in the terminal" for segmentation, that's a different (telemetry) decision and conflicts with the app's zero-telemetry stance.

---

## 7. Components: reuse vs. new

| Element | Reuse / New |
|---|---|
| Window chrome, winbody padding (32/40/28) | **Reuse** — same insets `ConnectorContainer` applies to every step. |
| `WindowFooter` + `BackLink` | **Reuse** verbatim. |
| Card-with-divided-rows + 18pt checkbox + sub-label | **Reuse** the `categorySection` / `rowView` / `checkbox` pattern from `MultiSelectStep` (lines 140–234). Could be extracted into a shared `SelectableRowCard` to DRY both screens — *optional refactor, flag for Rob*, not required. |
| Leading row icon (SF Symbol, accent, 22pt frame) | **Reuse** the icon treatment from `PermissionsStep.permissionCard` (lines 141–146). |
| `.tokenPrimary` (Continue) / `.tokenTextLink` (Skip) | **Reuse**. |
| **The triage step view itself** (`UsageTriageStep`) | **New** — a thin view. State: `@Binding var selectedMethods: Set<AccessMethod>` (new lightweight enum: `.browser/.desktop/.cli`), callbacks `onContinue/onSkip/onBack`. |
| `AccessMethod` enum + `AccessMethod → Set<ProviderId>` map | **New** — small model. Should live next to `BrandId.pools` in `Models/Provider.swift` so the two maps stay co-located and reviewable. |
| `multiSelect` row-filtering | **Modified** — `MultiSelectStep.groups` becomes a function of the selected methods (filter rows whose brand has no pool reachable by a selected method). Empty method set = show all. |
| `ConnectorContainer` flow | **Modified** — add `.usageTriage` case between `.permissions` and `.multiSelect`; move/seed detection earlier; add `triageSelection` `@State` with seed-once guard. |
| `PlanBuilder`, execution queue, `SetupPlanStep`, chooser | **Unchanged** — triage is a visibility filter only. |
