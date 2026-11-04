# Tokenomics — Future Features

A holding pen for ideas not yet scoped into a phase. The canonical product
roadmap lives in `docs/roadmap.md` — items in this file graduate there once
they're committed.

Last updated: 2026-04-27

---

## Multi-Machine Usage Sync (Codex + Gemini via CLI subprocess)

**Status:** Idea — blocked on upstream
**Origin:** Conversation 2026-04-27, OAuth feasibility spike for onboarding flow
**Phase fit:** Post-Phase-2, gated on upstream CLI features

### What

Surface usage data that reflects all of a user's machines, not just the Mac
running Tokenomics. Today, Codex and Gemini providers read local artifact
files only ("Path C") — fast, silent, policy-safe, but single-machine. A
user who codes on a second Mac (or, eventually, an iPad CLI) sees stale data
on the machine they're not actively using.

The proposed approach ("Path B") is to subprocess the official CLI with a
non-interactive usage flag (e.g. `codex usage --json`, `gemini stats --json`)
and parse stdout. Both CLIs internally fetch server-side aggregated usage,
so subprocess output would reflect all devices.

### Why

Narrowly scoped: power users with 2+ active **CLI-based coding machines**
(e.g. a desktop and a laptop both running Codex/Gemini CLI) feel a sync gap.
The 80% case is served fine by Path C; this addresses a small slice of
multi-Mac coders who want real-time agreement between machines.

### What this does NOT solve

This does **not** capture ChatGPT or Gemini consumer chat usage from phone
or web browser. CLI quotas and consumer-chat quotas are separate pools on
the same account — `codex usage --json` would still report the Codex
*coding* quota, not the chat quota. See the "Consumer AI Chat Usage
Tracking" entry below for that question.

### Onboarding cost

Path B requires the official CLI to be installed AND authenticated on every
machine being tracked. For users who only code on one Mac, this adds zero
value at the cost of CLI install friction. Phase 2 onboarding should keep
Path C as the default; Path B is opt-in advanced behavior.

### Blocked on

Neither CLI exposes usage as a non-interactive subcommand today. Slash
commands inside the TUI (`/status` for Codex, `/stats` for Gemini) exist but
aren't subprocess-friendly. Tracking upstream:

- [openai/codex#15281](https://github.com/openai/codex/issues/15281) —
  Expose full usage/limits data in CLI (`codex usage --json` requested)
- [google-gemini/gemini-cli#13842](https://github.com/google-gemini/gemini-cli/issues/13842)
  / [PR #13843](https://github.com/google-gemini/gemini-cli/pull/13843) —
  Show model usage limit remaining in `/stats`

Until at least one ships a stable JSON output, Path B isn't viable. The only
alternatives — TUI screen-scraping or replaying the CLI's internal API call
ourselves — are either too brittle or violate Google's third-party OAuth
policy ([discussion #22970](https://github.com/google-gemini/gemini-cli/discussions/22970)).

### Recommended shape (when unblocked)

Hybrid, not full replacement:

- **Default to Path C** (local artifact reader) for fast, silent polling
- **Trigger a single Path B subprocess refresh** when local data is >2h
  stale, when user opens the popover after idle, or on manual refresh
- **Surface staleness in UI** ("as of 23 min ago") so users understand what
  they're seeing — also useful before Path B ships, as a Path C improvement

### Risks to design around

- **Subprocess churn.** Each invocation = process startup + a network call.
  Don't poll on a tight interval; trigger only on need.
- **Auth interference.** CLI invocations may rotate refresh tokens (we've
  seen this with Claude Code). Need to test that subprocess calls don't log
  the user out of their CLI session.
- **Visibility.** Path C is invisible to users. Path B means Tokenomics
  actively launches the user's CLI. Some will dislike that. Hybrid (only on
  staleness) keeps the noise minimal.

### Not blocking

Phase 2 onboarding ships with Path C unchanged. This is purely additive when
upstream cooperates.

### Status check 2026-06-22

**openai/codex#15281** ("Feature: Expose full usage/limits data in CLI") — still **open**, zero
comments, no linked PR. Opened 2026-03-20. Request covers a new `codex usage --json` subcommand
and/or expanded `/status` output. No upstream signal of intent to implement. Codex Path B remains
fully blocked.

**google-gemini/gemini-cli#13842** — closed as duplicate of #13415 (also closed). The related
**PR #13843** ("Add usage limit remaining in /stats") was **merged 2025-11-27** and has shipped in
subsequent stable releases (latest: v0.47.0, 2026-06-18). However, the PR enhanced the *TUI*
`/stats` panel only — quota remaining and reset times now display interactively, but no
non-interactive `--json` flag or subprocess-parseable output was added. Subprocessing `/stats`
still produces TUI-formatted output, not machine-readable JSON. Gemini Path B remains blocked
pending a non-interactive output mode.

**Overall:** Both blockers are still active as of 2026-06-22. Gemini made meaningful partial
progress (the data now exists in the UI layer), but neither CLI exposes usage as a parseable
non-interactive subcommand. Path B is not yet actionable; no action needed on `docs/roadmap.md`.

---

## Consumer AI Chat Usage Tracking

**Status:** Strategic question — blocked on no public API
**Origin:** Conversation 2026-04-27, surfaced while discussing multi-machine sync
**Phase fit:** Speculative; expansion of Tokenomics' product scope

### What

Show usage of the consumer ChatGPT app (iOS/web) and consumer Gemini app
(iOS/web/Android) — not just AI coding tools. The audience is everyone, not
just developers, and many people primarily use AI through the consumer
chat surface on their phone or browser.

### Why

Tokenomics is a quota-awareness tool. If we expand its definition from
"AI coding tools" to "all AI usage I'm paying for," the addressable market
goes from developers to anyone with a paid AI subscription — a much larger
market that aligns with the menu bar's at-a-glance utility framing.

### Blocked on

There is **no public API** for reading consumer chat usage from any
provider:

- **OpenAI** — ChatGPT Plus/Pro chat usage is not exposed via any public
  endpoint. The Usage API covers paid developer API consumption, not Plus
  chat. Codex CLI's quota is a separate pool from ChatGPT chat.
- **Google** — Same situation. Consumer Gemini app usage is not exposed
  via any third-party API. Gemini CLI / Code Assist quotas are separate
  pools from consumer Gemini chat.

The providers do show this data in their own UIs ("X of Y messages used
this week") but they do not ship it to third parties, and there is no
sanctioned OAuth flow that grants read access to it.

### Why this can't piggyback Path B or Path C

- **Path B** (CLI subprocess) reports the CLI's coding quota, not the
  user's chat usage. Wrong pool.
- **Path C** (local artifact) only sees what the local CLI writes. The
  consumer apps are not the CLI and don't write to the same files.
- **Direct OAuth into consumer accounts** is not offered by either
  provider for usage data, and Google explicitly forbids third-party
  OAuth piggybacking ([gemini-cli discussion #22970](https://github.com/google-gemini/gemini-cli/discussions/22970)).

### Possible (speculative) paths forward

- **Wait for providers to ship a consumer usage API.** No signal either
  has plans to. Worth a quarterly recheck.
- **Browser extension / accessibility scrape.** Could read the "X of Y
  messages used" hint that ChatGPT/Gemini show in their own UI. Brittle,
  ToS-edge, and a totally different product surface from the menu bar.
- **User-reported usage.** Manual entry — defeats the at-a-glance value
  prop.

### Decision needed

Two coherent product positions:

1. **Stay focused on AI coding tools.** Sharpen positioning, drop the
   ambition to track consumer chat. Path C / Path B framing is sufficient.
2. **Expand scope to all paid AI usage.** Strategic bet that requires
   either provider cooperation or a non-trivial new product surface
   (extension, etc.). Significant build, uncertain payoff.

This is a positioning question to resolve before any engineering. Capturing
here so it doesn't get lost.

---

## Weekly Usage Insights Report

**Status:** Idea — not scoped
**Origin:** Conversation 2026-04-27, sparked by Claude Code's `/usage` insights output
**Phase fit:** Post-onboarding-simplification, likely v2.10+

### What

A weekly summary surface — email digest, in-app weekly view, or notification —
that delivers behavioral usage insights, not just raw bars. The popover stays
simple (current bars + reset times). The insights live somewhere with room to
explain.

Inspiration from Claude Code's `/usage` output:

> **99% of your usage came from subagent-heavy sessions.** Each subagent runs
> its own requests. Be deliberate about spawning them — and consider
> configuring a cheaper model for simpler subagents.
>
> **81% of your usage came from sessions active for 8+ hours.** These are
> often background/loop sessions. Continuous usage can add up quickly so make
> sure it is intentional.
>
> **72% of your usage was at >150k context.** Longer sessions are more
> expensive even when cached. /compact mid-task, /clear when switching to new
> tasks.

Tone: behavioral coaching, not surveillance. Claude Code's framing —
*"these are characteristics of your usage, not a breakdown"* — is exactly right.

### Why

Tokenomics' bars tell you *where you are* in your limits. They don't tell you
*why you are there* or *what to change*. The insights answer the second and
third questions, which is where the actual product value compounds. Bars are
ambient awareness; insights are coaching.

### Where the data lives (technical)

Two distinct sources:

- **Aggregate utilization** (the 5-hour and 7-day bars) → server-side, from
  `api.anthropic.com/api/oauth/usage`. Already integrated.
- **Behavioral insights** (subagent-heavy, 8+ hour sessions, >150k context) →
  computed locally by Claude Code from JSONL session files at
  `~/.claude/projects/`. Includes the disclaimer *"approximate, based on local
  sessions on this machine — does not include other devices or claude.ai."*

Tokenomics already does local JSONL parsing for Codex CLI (per v2.2.0 portfolio
entry — same pattern would extend to Claude Code session logs).

### Cross-provider differentiation

This is where Tokenomics outpaces Claude Code's own dashboard: a unified
weekly report with insights from **all** providers — Claude, Codex, Cursor,
Copilot — in one digest. Anthropic can't give you cross-provider insights.
Tokenomics can.

### Open questions

- Email digest, in-app weekly view, or both? Email is acquisition-friendly
  (forwardable, social proof); in-app respects the "stays on your Mac"
  privacy posture.
- Which insights generalize across providers, and which are Claude-specific?
- Opt-in by default or opt-out? Probably opt-in for email; opt-out for in-app.
- How does this feed the team-tier dashboard (roadmap Phase 2)? Aggregated
  team insights are a clear monetization wedge.

### Not blocking

This is a future-phase idea, not a Phase 1 follow-up. Captured here so it
doesn't get lost while onboarding-simplification work continues.

---

## How to add to this doc

When a future-phase idea surfaces, capture it here with at minimum:

- **Status:** Idea / Strategy committed / Plan not written / In progress
- **Origin:** Where the idea came from (conversation, customer feedback, etc.)
- **What:** One-paragraph plain-language description
- **Why:** Strategic rationale
- **Open questions:** What needs validation before scoping engineering

Keep entries terse. The goal is not a finished plan — it's preserving the
thinking so it isn't lost between sessions.

When an idea graduates to a committed phase, move it to `docs/roadmap.md`
and remove it from this file.
