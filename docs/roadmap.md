# Tokenomics — Product Roadmap

Last updated: 2026-03-09
Current version: 2.2.6 (build 15)
Active branch: feat/watch-app

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
- Notification threshold infrastructure (partially built)

---

## Phase 1: Provider Expansion (Current Sprint)

### Make `longWindow` optional on `ProviderUsageSnapshot`
**Status:** Up Next
**Priority:** High — blocking new provider work
**Why:** `ProviderUsageSnapshot` currently requires both `shortWindow` and `longWindow` as non-optional fields. Providers like Copilot have only one meaningful metric (premium requests). Forcing a fake `longWindow` is a data integrity problem — a zero-filled second ring sends a false signal. Making `longWindow: WindowUsage?` is a small model change with broad impact: it enables single-metric providers and simplifies future provider onboarding.
**Scope:** `Provider.swift` (model), any views that render `longWindow` (guard against nil, hide ring/bar if absent).
**Risk:** Low — additive change, existing providers keep non-nil values.

### Copilot Provider
**Status:** Backlog
**Priority:** High — large user base, official API available
**Auth:** GitHub Personal Access Token (PAT), stored in Keychain
**Data source:** GitHub REST API — Copilot usage endpoints
**Metrics to track:** Premium requests used / limit (the only quota GitHub exposes)
**Ring layout:** Single ring (inner only, `longWindow` nil) — requires the optional `longWindow` change above
**Notes:** GitHub's Copilot API is official and documented. PAT auth means no OAuth dance. Premium request quota is the meaningful constraint for Max users; Basic users have unlimited standard requests.

### Cursor Provider
**Status:** Backlog
**Priority:** High — widely used by the Tokenomics target persona
**Auth:** No API auth needed — reads local state file
**Data source:** `~/.cursor/User/globalStorage/state.vscdb` (SQLite)
**Metrics to track:** Token credits consumed from credit pool, remaining balance
**Ring layout:** Single or dual ring depending on what the schema exposes (needs investigation)
**Notes:** No official API. SQLite extraction is the same pattern as Codex JSONL tail-reading — local read, no network. Credit pool tracking is the primary value for paid Cursor users. Schema may change across Cursor versions; needs a version-tolerant parser.
**Risk:** Medium — undocumented schema, subject to change without notice.

### Midjourney Provider
**Status:** Placeholder
**Priority:** Low — no API yet
**Why placeholder:** Midjourney has announced but not shipped a public API. Building against a scrape or unofficial endpoint is fragile and against ToS. The right call is a visible "coming soon" state in the provider list — signals intent, sets expectation, requires no maintenance.
**Trigger to build:** Official Midjourney API GA with usage/credit endpoints.

### Runway Provider
**Status:** Backlog
**Priority:** Medium
**Auth:** Runway API key, stored in Keychain
**Data source:** Runway REST API (official, credit balance endpoints)
**Metrics to track:** API credit balance / monthly allocation
**Ring layout:** Single ring (credits remaining as utilization)
**Notes:** Runway is less common in the AI coding tool persona but relevant for design-adjacent users. Official API makes this straightforward once `longWindow` is optional.

---

## Phase 2: Agent Approval Notifications

This phase transforms Tokenomics from passive usage monitor to active agent management tool.

### Context
AI agents (Claude Code, Codex, Cursor) increasingly pause mid-task and require user approval before proceeding — file writes, shell commands, web fetches. Today, the user must be at their desk watching the terminal. The "go get coffee" problem: agents run autonomously, hit an approval gate, and stall until the user notices.

The watch app use case that makes this real: a user starts a long agent task, walks away, and approves the next step from their wrist without returning to the desk. Usage monitoring on watch is a nice-to-have. Approval from watch is a genuine workflow unlock.

### Usage Threshold Notifications (macOS)
**Status:** Backlog (infrastructure partially built)
**Priority:** Medium
**What:** Push notification when a provider's utilization crosses a threshold (e.g., "Claude Code is at 80% — 1 hour of headroom left").
**Notes:** `NotificationService.swift` exists. The threshold logic and user-configurable thresholds in Settings are the remaining work. Low-complexity addition on top of existing infrastructure.

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
**Notes:** The current branch appears to be building the watch app. The framing shift matters for what gets built first: approval UI before usage rings, not after. A watch app that only shows a percentage ring is a novelty. A watch app that lets you unblock a running agent is a tool.

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
- **Phase 1 (Provider Expansion):** Strengthens free tier. More providers = more users.
- **Phase 2 (Agent Approval):** First genuine paid-tier candidate. "Would you pay to check a usage ring on your wrist?" is a weak hook. "Would you pay to approve and unblock a running AI agent from your watch?" is a real value proposition.
- **Phase 3 (Cross-Platform):** Unlocks Windows/Linux market. Requires paid tier to justify ongoing maintenance.
- **Team tier (future):** See who on your team is running agents, approve on their behalf, aggregate usage dashboards. This is a B2B play and a much larger market than individual tool monitoring.

### Connection to Cortex Vision
Tokenomics started as a usage monitor. The approval flow positions it as the user-facing control layer for AI agent orchestration — closer to what "Cortex" (cross-platform, cross-memory AI coordination) would need as a management interface. Keep this framing in mind when making architecture decisions: data models and notification infrastructure built for approval flows should be designed as if a broader orchestration layer will depend on them later.

### Architectural Watch Item
Making `longWindow` optional is a prerequisite for every new provider in Phase 1. Don't merge any new provider work until that change ships. Building Copilot or Runway with a fake `longWindow` creates a debt that's annoying to unwind later.

---

## Technical Debt Log

| Item | Logged | Notes |
|------|--------|-------|
| `longWindow` non-optional on `ProviderUsageSnapshot` | 2026-03-09 | Blocks single-metric providers. Fix before adding Copilot or Runway. |
| Notification threshold UI not exposed in Settings | 2026-03-09 | `NotificationService.swift` exists, Settings integration is missing. |
| Cursor provider schema unknown | 2026-03-09 | Needs investigation of `state.vscdb` structure before estimating scope. |
| Agent approval interception mechanism unknown | 2026-03-09 | Spike required before committing to Phase 2 implementation. |

---

## Dropped / Deferred

### Multi-pin menu bar (multiple simultaneous providers in menu bar)
**Status:** Dropped
**Why:** `MenuBarExtra` has a hard width cap (~80–100pt). Two ring sets overflows it. Replaced with radio-button single-pin + Smart mode (worst-of-N). Decision made in v2.0.
