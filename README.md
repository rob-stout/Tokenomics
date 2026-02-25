# Tokenomics

A macOS menu bar app that shows your Claude Code API usage at a glance — built for developers who want to know how much quota they have left without opening a browser.

<img width="330" height="313" alt="image" src="https://github.com/user-attachments/assets/87938acc-e2d9-4bce-9ee7-a0ef1a66a44b" />


---

## Prerequisites

- macOS 13 Ventura or later
- Claude Code installed and signed in (`claude login` run at least once)

---

## Installation

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the `.dmg` and drag **Tokenomics** into your Applications folder
3. Launch Tokenomics — if Gatekeeper prompts you, open **System Settings → Privacy & Security** and click **Open Anyway**

---

## First-Run Setup

Tokenomics reads your OAuth token from the macOS Keychain, where Claude Code stores it after you authenticate. No manual token entry required.

1. Open Terminal and run `claude` to confirm you are signed in (or to sign in fresh)
2. Launch Tokenomics from Applications
3. Click the icon that appears in the menu bar — your usage data loads within a few seconds

---

## What It Shows

Click the menu bar icon to open the popover:

| Section | Description |
|---|---|
| **5-Hour Window** | Token usage for the current rolling 5-hour period, with time until reset |
| **7-Day Window** | Token usage for the current rolling 7-day period, with time until reset |
| **Extra Usage** | Dollar-denominated overage spend against your monthly cap (Max plan only) |
| **Plan badge** | Your plan (Free / Pro / Max), inferred from the API response shape |
| **Last synced** | Timestamp of the most recent successful fetch, with a manual Refresh button |
| **Launch at Login** | Toggle to start Tokenomics automatically when you log in to macOS |

---

## Menu Bar Icon Guide

The icon renders two concentric rings that update every 5 minutes.

```
  [ outer ring ]  =  7-day usage window   (dimmer, 40% opacity)
  [ inner ring ]  =  5-hour usage window  (brighter, 50% opacity)
  [ dim track  ]  =  full capacity of the window (background circle)
  [ bright dot ]  =  pace marker
```

**How to read it:**

- Each ring fills clockwise from 12 o'clock as you consume tokens
- The **track** (dim background ring) represents 100% capacity for that window
- The **pace dot** on each ring shows where your usage fill would sit if your token consumption were spread perfectly evenly across the entire window — it moves forward in real time as the window elapses
- If the fill arc is **ahead of the pace dot**, you are burning tokens faster than your average rate
- If the fill arc is **behind the pace dot**, you have headroom relative to your typical pace

The percentage next to the icon always reflects the 5-hour window — the number most likely to change and most relevant for day-to-day work.

**Icon states:**

| Icon | Meaning |
|---|---|
| Rings + percentage | Normal — data loaded |
| `—` with rings | Loading on first launch |
| Person icon | Not signed in |
| Triangle warning | Error fetching data |

---

## How It Works

1. On launch, Tokenomics reads your Claude OAuth access token from the macOS Keychain entry written by Claude Code (`Claude Code-credentials`)
2. It calls `https://api.anthropic.com/api/oauth/usage` with your token as a Bearer credential
3. Usage data is refreshed every **5 minutes** in the background
4. The token is cached in memory — it is never written to disk or sent anywhere other than the Anthropic API

---

## Troubleshooting

**"Session expired" error**
Your OAuth token has rotated. Run `claude` in Terminal (this re-authenticates Claude Code and writes a fresh token to Keychain), then click **Refresh** in the Tokenomics popover. You do not need to relaunch the app.

**Plan badge shows the wrong plan**
The plan is inferred from the shape of the API response, not a stored preference. Sign out of Claude Code (`claude logout`) and back in (`claude login`), then click Refresh.

**No icon appears in the menu bar**
Confirm Claude Code is installed and that you have run `claude login` at least once. If the app was blocked by Gatekeeper, follow the "Open Anyway" step in Installation above.

**Usage numbers look stale**
Click the **Refresh** button in the popover footer to trigger an immediate fetch outside the 5-minute cycle.

---

## Privacy

- Tokenomics makes exactly one outbound network call: `GET https://api.anthropic.com/api/oauth/usage`
- No analytics, no telemetry, no third-party SDKs
- Your token is read from Keychain at launch and held in memory only — it is never written to disk by Tokenomics
- No usage data leaves your machine except to the Anthropic endpoint that owns it

---

## License

MIT — see [LICENSE](LICENSE)
