# Tokenomics Privacy Policy

**Effective date:** March 4, 2026
**Author:** Rob Stout (rob@robstout.design)

---

## What Tokenomics accesses

Tokenomics reads authentication credentials stored locally on your Mac by the AI coding tools you have installed:

- **Claude Code** — OAuth token from macOS Keychain (`Claude Code-credentials`)
- **OpenAI Codex CLI** — OAuth token from `~/.codex/auth.json`
- **Google Gemini CLI** — OAuth credentials from `~/.gemini/oauth_creds.json`

These credentials are read into memory at launch. They are never written to disk, logged, or transmitted anywhere by Tokenomics other than to the provider endpoints described below.

## Network calls Tokenomics makes

Tokenomics makes outbound API calls only to the provider endpoints that own your usage data:

| Provider | Endpoint |
|---|---|
| Anthropic | `https://api.anthropic.com/api/oauth/usage` |

OpenAI and Google usage data is read from local session files — no network calls are made for those providers.

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
