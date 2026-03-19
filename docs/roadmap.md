# Tokenomics — Product Roadmap

Last updated: 2026-03-17
Current version: 2.5.0 (build 27)

---

## Legend

| Status | Meaning |
|--------|---------|
| Done | Shipped in a released version |
| In Progress | Active development, current sprint |
| Up Next | Committed, not yet started |
| Backlog | Validated idea, not yet scheduled |
| Placeholder | Intentional "coming soon" — dependency on external factor |
| Dropped | Considered and rejected — reason noted |

---

## Shipped

### v1.x — Foundation
- Claude Code usage rings (5-hour + 7-day rate limit windows)
- macOS menu bar agent (LSUIElement, no Dock icon)
- Popover with animated usage bars and pace indicator dots
- Sparkle auto-update pipeline
- `distribute.sh` release script (build → sign → notarize → DMG → appcast)
- Settings behind gear icon (progressive disclosure)
- About view as UI legend (behavioral ring descriptions)

### v2.0–v2.2 — Multi-Provider + Distribution
- Codex CLI provider (SQLite/JSONL context window tracking)
- Gemini CLI provider (local session file parsing, plan-selection flow)
- `UsageProvider` protocol — provider-agnostic architecture
- `ProviderUsageSnapshot` / `WindowUsage` data model
- `sublabelOverride` field on `WindowUsage` (escape hatch for non-time-based windows)
- Smart mode (worst-of-N utilization in menu bar)
- Single-pin mode (radio-button provider pinning)
- macOS WidgetKit extension (small + medium, Smart or per-provider)
- App Group file-based data store (sidesteps CFPrefs sandbox boundary)
- Three-layer OAuth rate limit defense (proactive refresh + reactive 429 + cached fallback)
- "Updated Xm ago" stale data microcopy
- IA split: "How It Works" + "About Tokenomics" as separate screens
- Homebrew Cask distribution (`brew install --cask tokenomics`)
- Source-available license (portfolio visibility + monetization optionality)
- Legal section in About view (Privacy Policy + non-affiliation disclaimer)
- Per-provider notification thresholds with configurable alert windows (Short/Long/Both)

### v2.3–v2.5 — Provider Expansion + Widget Polish
- `longWindow` made optional on `ProviderUsageSnapshot` — unblocks single-metric providers
- Copilot provider (zero-friction auth via `gh` CLI, premium request tracking)
- Cursor provider (local SQLite state file, credit pool tracking)
- Provider icons (light/dark variants for all providers)
- Provider reorder (drag) and show/hide visibility controls
- Per-provider poll intervals and notification thresholds
- Exponential backoff on 429 (5m → 10m → 20m → 40m → 1h cap)
- Activity-aware polling
- Settings redesign with grouped sections and icons
- Large widget support (up to 7 providers, adaptive layouts)
- Widget share CTA + deep link URL scheme (`tokenomics://`)
- Sparkle auto-check enabled

---

## Phase 1: Provider Expansion (continued)

Phase 1 coding providers are shipped. Remaining work is ecosystem renames, creative AI providers, and the Connections page redesign to support both.

### Ecosystem Extensions

#### Rename Codex CLI → OpenAI
**Status:** Backlog
**Priority:** Medium
**What:** Codex CLI, DALL-E, and Sora share the same OpenAI billing pool. Rename the provider to "OpenAI" and surface additional metrics for image and video credit consumption alongside existing token tracking. One provider, one connection, multiple metrics.
**Scope:** Provider label change everywhere it appears (menu bar, popover, settings, widgets). Add DALL-E image credits and Sora video credits as additional metric rows in the detail view.
**Risk:** Low code complexity. User-visible label change needs a migration note in the release.
**Note:** Provider icon is already the OpenAI logo — no icon change needed.

#### Rename Gemini CLI → Google AI
**Status:** Backlog
**Priority:** Medium
**What:** Gemini CLI, Nano Banana 2 (image gen), and Veo (video gen) share Google AI credits (Pro: 1,000/mo, Ultra: 25,000/mo). Rename to "Google AI" and extend with image/video credit consumption. Plan-selection flow already exists.
**Scope:** Same as OpenAI rename — label change + additional metrics in detail view.
**Risk:** Low. Existing plan-selection UI carries over. Same label migration caveat.
**Note:** Provider icon is already the Google AI logo — no icon change needed.

### Standalone Creative Providers

#### ElevenLabs Provider
**Status:** Backlog
**Priority:** High — clear API, clear quotas, strong creative-user demand
**Auth:** ElevenLabs API key, stored in Keychain
**Data source:** ElevenLabs REST API — `/v1/user/subscription` endpoint returns character quota used and monthly limit
**Metrics to track:** Characters generated / monthly character limit
**Ring layout:** Single ring (`longWindow` nil)
**Notes:** Clearest win in this phase. Official API, well-documented, character quota maps cleanly to the ring metaphor. API key auth means no OAuth complexity.
**Risk:** Low.

#### Runway Provider
**Status:** Backlog
**Priority:** Medium
**Auth:** Runway API key, stored in Keychain
**Data source:** Runway REST API (official, credit balance endpoints)
**Metrics to track:** API credit balance / monthly allocation
**Ring layout:** Single ring (credits remaining as utilization, `longWindow` nil)
**Notes:** Design-adjacent user persona overlaps with Tokenomics target. Official API makes this straightforward.
**Risk:** Low.

#### Stable Diffusion Provider (via Stability AI)
**Status:** Backlog
**Priority:** Low
**Auth:** Stability AI API key
**Data source:** Stability AI REST API — credit balance endpoints
**Metrics to track:** Credit balance / allocation
**Ring layout:** Single ring
**Notes:** API available and credit-based. Lower priority than ElevenLabs and Runway due to smaller overlap with core user persona.
**Risk:** Low.

#### Midjourney Provider
**Status:** Placeholder
**Priority:** Low — no API yet
**Why placeholder:** No public API. Building against scrape or unofficial endpoints is fragile and against ToS.
**Trigger to build:** Official Midjourney API GA with usage/credit endpoints.

#### Suno Provider
**Status:** Placeholder
**Priority:** Low — no public API yet
**Why placeholder:** Music generation is credit-based, but credits are not queryable programmatically.
**Trigger to build:** Suno public API GA with credit/usage endpoints.
**Notes:** High-engagement creative tool — worth the placeholder to signal intent.

#### Udio Provider
**Status:** Placeholder
**Priority:** Low — no public API yet
**Why placeholder:** Same situation as Suno. Credit-based billing, no public API.
**Trigger to build:** Udio public API GA with credit/usage endpoints.
**Notes:** Udio and Suno are direct competitors. If one ships an API first, the other typically follows.

### Connections Page Redesign

**Status:** Up Next — design in progress (mockups at `mocks/connections-mockup.html`)
**Priority:** High — gates ecosystem rename work
**What:** Redesign the Providers settings page to support the expanded provider landscape.

**Design decisions (2026-03-17):**

1. **Section-based organization (no drag reorder in settings).** Providers grouped into fixed sections: Platforms, Coding Tools, Image Generation, Video Generation, Music / Audio / Voice. Reordering happens in the popover only.

2. **Three-state provider model:**
   - Not Connected → "Connect" button (or "Coming Soon" if no API)
   - Connected + Visible → Toggle ON, green status text
   - Connected + Hidden → Toggle OFF, "Disconnect" button appears for full credential removal

3. **Platforms section** for shared-pool ecosystems (OpenAI, Google AI). One toggle per ecosystem, with text subtitle listing what's in the shared pool ("Codex CLI · DALL-E · Sora"). No per-service sub-toggles — connecting to the ecosystem connects to all services in the pool.

4. **Popover and widgets stay flat.** No sections, free drag reorder. The organizational structure lives in settings only.

---

## Phase 2: Agent Approval Notifications

This phase transforms Tokenomics from passive usage monitor to active agent management tool.

### Context
AI agents (Claude Code, Codex, Cursor) increasingly pause mid-task and require user approval before proceeding — file writes, shell commands, web fetches. Today, the user must be at their desk watching the terminal. The "go get coffee" problem: agents run autonomously, hit an approval gate, and stall until the user notices.

The watch app use case that makes this real: a user starts a long agent task, walks away, and approves the next step from their wrist without returning to the desk. Usage monitoring on watch is a nice-to-have. Approval from watch is a genuine workflow unlock.

### Agent Approval Request Notifications
**Status:** Backlog
**Priority:** High (defines the watch/phone value proposition)
**What:** A notification layer that surfaces agent approval requests from Claude Code, Codex, and Cursor:
- macOS: Notification Center alert + menu bar indicator (badge or animated state)
- watchOS: Tap-to-approve from wrist (primary watch use case)
- iOS: Approve from phone when away from desk

**How approval interception works (needs investigation):**
- Claude Code: pipes approval prompts to stdout/stderr — may be readable via process monitoring or a named pipe/socket bridge
- Codex: similar stdio-based interaction model
- Cursor: approval dialogs are in-IDE — may require a VS Code extension bridge
- All three: investigate whether approval state can be written back (approve/reject) or whether notification is one-way (alert only, user still returns to terminal)

**Risk:** High — this is the most architecturally novel piece of work in this roadmap. The interception mechanism is not documented and varies per agent. Recommend a spike (2–4 hours) before committing to implementation. If write-back isn't feasible, a "heads up, your agent is waiting" notification is still valuable as a first version.

**Trigger to start:** Spike on Claude Code approval interception. If it works, sequence Codex and Cursor after.

### watchOS Companion App
**Status:** In Progress (feat/watch-app branch)
**Priority:** High — approval is the primary use case, not usage monitoring
**Primary use case:** Receive agent approval requests, tap to approve, return to what you were doing
**Secondary use case:** Glance at usage utilization across providers
**Notes:** The framing shift matters for what gets built first: approval UI before usage rings, not after. A watch app that only shows a percentage ring is a novelty. A watch app that lets you unblock a running agent is a tool.

### iOS Companion App
**Status:** Backlog
**Priority:** Medium — follows watchOS, shares approval infrastructure
**Primary use case:** Full usage dashboard + agent approval when away from Mac
**Notes:** iOS is the natural middle ground — better screen real estate than watch for a usage dashboard, more always-available than Mac for approvals. Build approval infrastructure in Phase 2 (macOS + watch), then iOS is mostly a new surface for existing logic.

---

## Phase 3: Cross-Platform

### Tauri App (Windows / Linux)
**Status:** Backlog
**Priority:** Low — significant scope, small immediate payoff
**Why eventually:** The Tokenomics target user is not Mac-exclusive. Cursor and Copilot users on Windows are a large segment. A Tauri port reuses provider logic (Rust or JS) with platform-native credential stores (Windows Credential Manager, libsecret on Linux).
**Prerequisite:** Provider abstraction is stable and well-tested on macOS first. Don't port a moving target.
**Risk:** Medium — Tauri apps require maintaining a second codebase surface. Consider whether a web-based companion (read-only dashboard) is a lower-cost alternative before committing to Tauri.

---

## Strategic Notes

### Product Framing Shift
The original pitch for watch support was "check your usage ring from your wrist." That's a weak use case — you can see usage in the menu bar at your desk, and a percentage on your wrist doesn't change your behavior.

The correct framing: **Tokenomics is the control plane for your AI tools.** The watch app exists so you can manage running agents without returning to your desk. This reframes every Phase 2 decision — approval UI is table stakes for watch/phone, not a bonus feature.

### Revenue Path
- **Phase 1 (Provider Expansion):** Strengthens free tier. More providers = more users. Creative AI providers widen the addressable market beyond coding-only users.
- **Phase 2 (Agent Approval):** First genuine paid-tier candidate. "Would you pay to approve and unblock a running AI agent from your watch?" is a real value proposition.
- **Phase 3 (Cross-Platform):** Unlocks Windows/Linux market. Requires paid tier to justify ongoing maintenance.
- **Team tier (future):** See who on your team is running agents, approve on their behalf, aggregate usage dashboards. This is a B2B play and a much larger market than individual tool monitoring.

### Connection to Cortex Vision
Tokenomics started as a usage monitor. The approval flow positions it as the user-facing control layer for AI agent orchestration — closer to what "Cortex" (cross-platform, cross-memory AI coordination) would need as a management interface. Keep this framing in mind when making architecture decisions: data models and notification infrastructure built for approval flows should be designed as if a broader orchestration layer will depend on them later.

---

## Technical Debt Log

| Item | Logged | Notes |
|------|--------|-------|
| Agent approval interception mechanism unknown | 2026-03-09 | Spike required before committing to Phase 2 implementation. |
| Provider rename: Codex CLI → OpenAI | 2026-03-17 | User-visible label change. Needs migration note. Gates creative AI metrics on OpenAI ecosystem. |
| Provider rename: Gemini CLI → Google AI | 2026-03-17 | Same as above. Confirm plan-selection flow works after rename. |
| Connections page doesn't model shared billing pools | 2026-03-17 | Design in progress (`mocks/connections-mockup.html`). Must ship before ecosystem renames. |

---

## Dropped / Deferred

### Multi-pin menu bar (multiple simultaneous providers in menu bar)
**Status:** Dropped
**Why:** `MenuBarExtra` has a hard width cap (~80–100pt). Two ring sets overflows it. Replaced with radio-button single-pin + Smart mode (worst-of-N). Decision made in v2.0.
