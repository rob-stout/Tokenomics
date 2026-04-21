# Tokenomics Privacy Policy

**Effective date:** April 21, 2026
**Author:** Rob Stout (rob@robstout.design)

---

## What Tokenomics accesses

Tokenomics reads authentication credentials stored locally on your Mac by the AI tools you have installed:

- **Claude Code** — OAuth token from macOS Keychain (`Claude Code-credentials`)
- **GitHub Copilot** — OAuth token via the `gh` CLI
- **Cursor** — session token from Cursor's local config
- **OpenAI Codex CLI** — OAuth token from `~/.codex/auth.json`
- **Google Gemini CLI** — OAuth credentials from `~/.gemini/oauth_creds.json`
- **Stability AI, Runway, ElevenLabs** — API keys you paste into Tokenomics, stored in the macOS Keychain

These credentials are read into memory as needed and are never written to disk by Tokenomics, logged, or transmitted anywhere other than to the provider endpoints described below.

## Network calls Tokenomics makes

Tokenomics makes outbound API calls only to the provider endpoints that own your usage data:

| Provider | Endpoint(s) |
|---|---|
| Anthropic | `https://api.anthropic.com/api/oauth/usage`, `https://platform.claude.com/v1/oauth/token` (token refresh) |
| GitHub | `https://api.github.com/copilot_internal/user` |
| Cursor | `https://cursor.com/api/usage-summary` |
| Stability AI | `https://api.stability.ai/v1/user/balance` |
| Runway | `https://api.dev.runwayml.com/v1/credits` |
| ElevenLabs | `https://api.elevenlabs.io/v1/user/subscription` |

OpenAI and Google usage data is read from local CLI session files — no network calls are made for those providers. Midjourney, Suno, and Udio currently ship as placeholder tiles; Tokenomics does not read credentials or make network calls for them.

Tokenomics also checks for app updates via [Sparkle](https://sparkle-project.org), which contacts:

| Purpose | URL |
|---|---|
| Update check | `https://raw.githubusercontent.com/rob-stout/Tokenomics/main/appcast.xml` |

## What Tokenomics does NOT do

- No analytics or telemetry of any kind
- No third-party SDKs
- No data collection, aggregation, or transmission to any server controlled by the author
- No tracking of how you use the app
- No crash reporting

## Data retention

Tokenomics holds your credentials and usage data in memory while the app is running. When you quit Tokenomics, all data is discarded. Nothing is persisted to disk.

## Changes to this policy

If this policy changes, the updated version will be published in this repository with a new effective date. Significant changes will be noted in the release notes.

## Contact

Questions about this policy: rob@robstout.design
