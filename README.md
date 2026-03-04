# Tokenomics

A macOS menu bar app that shows your AI coding tool usage at a glance — supports Claude Code, Codex CLI, and Gemini CLI. Built for developers who want to know how much quota they have left without opening a browser.

<img width="330" height="313" alt="image" src="https://github.com/user-attachments/assets/87938acc-e2d9-4bce-9ee7-a0ef1a66a44b" />


---

## Prerequisites

- macOS 13 Ventura or later
- At least one supported AI coding tool installed and signed in:
  - **Claude Code** — run `claude login` at least once
  - **Codex CLI** — run `codex` at least once (credentials stored in `~/.codex/`)
  - **Gemini CLI** — run `gemini` at least once (credentials stored in `~/.gemini/`)

---

## Installation

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the `.dmg` and drag **Tokenomics** into your Applications folder
3. Launch Tokenomics — if Gatekeeper prompts you, open **System Settings → Privacy & Security** and click **Open Anyway**

---

## First-Run Setup

Tokenomics automatically detects which AI coding tools you have installed and reads their credentials from local storage. No manual token entry required.

1. Confirm at least one provider is signed in:
   - Claude Code: run `claude` in Terminal
   - Codex CLI: run `codex` in Terminal
   - Gemini CLI: run `gemini` in Terminal
2. Launch Tokenomics from Applications
3. Click the icon that appears in the menu bar — your usage data loads within a few seconds

---

## What It Shows

Click the menu bar icon to open the popover:

| Section | Description |
|---|---|
| **First bar (inner ring)** | Your most immediate constraint — the limit you're closest to hitting. Claude: 5-hour rate limit. Codex: rate limit window. Gemini: daily token budget. |
| **Second bar (outer ring)** | Broader usage context — a longer-horizon or secondary metric. Claude: 7-day rate limit. Codex: model context window. Gemini: daily request limit. |
| **Extra Usage** | Dollar-denominated overage spend against your monthly cap (Max plan only) |
| **Plan badge** | Your plan tier per provider. Claude and Codex plans are detected automatically; Gemini's plan is set by you |
| **Last synced** | Timestamp of the most recent successful fetch, with a manual Refresh button |
| **Launch at Login** | Toggle to start Tokenomics automatically when you log in to macOS |

---

## Menu Bar Icon Guide

The icon renders two concentric rings that update every 5 minutes.

```
  [ inner ring ]  =  your nearest limit — the constraint you're closest to hitting  (brighter)
  [ outer ring ]  =  broader context — a wider view of your usage trajectory         (dimmer)
  [ dim track  ]  =  full capacity of the window (background circle)
  [ bright dot ]  =  pace marker
```

**How to read it:**

- Each ring fills clockwise from 12 o'clock as you consume quota
- The **track** (dim background ring) represents 100% capacity for that window
- The **pace dot** on each ring shows where your fill would sit if usage were spread perfectly evenly across the window — it moves forward in real time as the window elapses
- If the fill arc is **ahead of the pace dot**, you are consuming faster than your average rate
- If the fill arc is **behind the pace dot**, you have headroom relative to your typical pace
- Pace dots only appear on time-based windows — not on the Codex context window

The percentage next to the icon always reflects the inner ring — the limit you're closest to hitting.

**What each ring shows by provider:**

| Provider | Inner ring | Outer ring |
|---|---|---|
| Claude Code | 5-hour rate limit | 7-day rate limit |
| Codex CLI | Rate limit window | Model context window (no pace dot) |
| Gemini CLI | Daily token budget (estimated) | Daily request limit (estimated) |

**Icon states:**

| Icon | Meaning |
|---|---|
| Rings + percentage | Normal — data loaded |
| `—` with rings | Loading on first launch |
| Person icon | Not signed in |
| Triangle warning | Error fetching data |

---

## How It Works

Tokenomics reads credentials from local sources for each detected provider:

| Provider | Credential source | Data method |
|---|---|---|
| **Claude Code** | OAuth token from macOS Keychain (`Claude Code-credentials`) | API call to `api.anthropic.com` |
| **Codex CLI** | Session files in `~/.codex/sessions/` | Local file reads |
| **Gemini CLI** | Session files in `~/.gemini/` | Local file reads |

- Usage data is refreshed every **5 minutes** in the background
- Credentials are held in memory only — never written to disk by Tokenomics
- Only Claude Code requires a network call; Codex and Gemini usage is read entirely from local files

---

## Troubleshooting

**"Session expired" error (Claude Code)**
Your OAuth token has rotated. Run `claude` in Terminal (this re-authenticates and writes a fresh token to Keychain), then click **Refresh** in the Tokenomics popover. You do not need to relaunch the app.

**Plan badge shows the wrong plan**
The plan is inferred from available API data, not a stored preference. Sign out and back into the relevant provider, then click Refresh.

**No icon appears in the menu bar**
Confirm at least one supported provider is installed and signed in. If the app was blocked by Gatekeeper, follow the "Open Anyway" step in Installation above.

**A provider is missing from the popover**
Tokenomics auto-detects providers by checking for their credentials on disk. Make sure you've signed in to the provider at least once (e.g., `claude login`, `codex`, `gemini`), then click Refresh.

**Usage numbers look stale**
Click the **Refresh** button in the popover footer to trigger an immediate fetch outside the 5-minute cycle.

---

## Privacy

- Tokenomics makes outbound API calls only to the provider endpoints that own your data (Anthropic, OpenAI, Google) to fetch your usage information
- Tokenomics checks for updates via [Sparkle](https://sparkle-project.org), which contacts the appcast URL hosted on GitHub to check for new versions
- No analytics, no telemetry, no third-party SDKs
- Your tokens are read from local sources (Keychain, config files) at launch and held in memory only — they are never written to disk by Tokenomics
- No usage data leaves your machine except to the provider endpoints that own it

For the full privacy policy, see [PRIVACY.md](docs/PRIVACY.md).

---

## Support

Tokenomics is free and built with care. If you find it useful, consider supporting its development:

- [GitHub Sponsors](https://github.com/sponsors/rob-stout)

---

## License

Source Available — free to use and share with attribution. See [LICENSE](LICENSE) for details.

Tokenomics is not affiliated with, endorsed by, or sponsored by Anthropic PBC, OpenAI Inc., or Google LLC.
