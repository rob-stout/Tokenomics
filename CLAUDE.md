# Tokenomics

macOS menu bar app that shows AI coding tool usage at a glance.
Supports Claude Code, Codex CLI, Gemini CLI, GitHub Copilot, and Cursor.

**Platform skill:** native **macOS** (SwiftUI menu-bar) → load `platform-macos` for the app + `TokenomicsWidgets`. For work under `extension/` (MV3 browser extension — `manifest.json`, content scripts, `chrome.*`) load `platform-browser-extension` instead. (The `tokenomics-*` sibling dirs are worktrees of this repo and share this file.)

## Tech Stack
- **UI**: SwiftUI (macOS 13+)
- **Architecture**: MVVM with @Observable
- **Updates**: Sparkle framework (EdDSA signed, auto-update via appcast.xml)
- **Distribution**: Developer ID signed .dmg via GitHub Releases + Homebrew cask
- **Build config**: xcodegen (`project.yml` → Xcode project)

## Project Structure
```
Tokenomics/
├── App/             # App entry point, menu bar setup
├── Models/          # Data models (Provider, UsageData, GeminiPlan, AppError)
├── Views/           # SwiftUI views (popover, settings, onboarding, about)
├── ViewModels/      # @Observable view models
├── Services/        # Per-provider API clients, polling, notifications, widget data, settings
└── Resources/       # Assets, provider icons (light/dark), entitlements

TokenomicsWidgets/   # macOS desktop widget extension (small/medium/large)
TokenomicsSafari/            # "Tokenomics for Safari" — sandboxed Mac App Store companion app
TokenomicsSafariExtension/   # Safari Web Extension appex, embedded in TokenomicsSafari
Casks/               # Homebrew cask definition (tokenomics.rb)
scripts/             # distribute.sh (DMG) + distribute-appstore.sh (Mac App Store)
```

## Providers
Each provider has its own service file in `Services/`:
- **Claude Code** — reads token from `~/.claude/` credentials file
- **Codex CLI** — reads from `~/.codex/`
- **Gemini CLI** — reads from `~/.gemini/`
- **GitHub Copilot** — zero-friction auth via `gh` CLI
- **Cursor** — reads from local Cursor config

Providers support: reordering (drag), show/hide visibility, per-provider poll intervals, per-provider notification thresholds, and provider icons (light/dark variants).

## Key Features
- **Menu bar rings** — at-a-glance usage rings in the menu bar
- **Tabbed popover** — per-provider usage details with provider icons
- **Desktop widgets** — small/medium/large widget sizes with adaptive layouts (up to 7 providers in large)
- **Deep link URL scheme** — `tokenomics://` for opening from widgets (share CTA)
- **Notifications** — per-provider threshold alerts
- **Rate limiting** — exponential backoff on 429 (5m → 10m → 20m → 40m → 1h cap), per-provider poll intervals
- **Activity-aware polling** — reduces API calls when idle
- **Settings** — grouped sections with icons, provider reorder/visibility controls

## Commands
```bash
xcodegen generate              # Regenerate Xcode project from project.yml (run AFTER version bumps)
./scripts/distribute.sh        # Build, sign, notarize, create DMG, upload to GitHub Releases
node extension/build.mjs --safari    # Build the Safari Web Extension bundle — REQUIRED before
                                      # building the TokenomicsSafari scheme (produces extension/dist-safari/)
./scripts/distribute-appstore.sh     # Validate (and, with --upload, publish) the Mac App Store companion
git config core.hooksPath .githooks  # ONE-TIME per clone: enable auto-xcodegen on branch switch
```

The `.githooks/post-checkout` hook auto-runs `xcodegen generate` after branch
switches when `project.yml` or any `.swift` file differs between the two
branches. Avoids "Build input files cannot be found" errors when bouncing
between branches with different source trees.

## Release Process
1. Bump version in `project.yml` (both targets: main app + widgets)
2. `xcodegen generate` — must run AFTER version bump
3. `./scripts/distribute.sh` — builds, signs, notarizes, creates DMG, uploads to GitHub
4. Update `Casks/tokenomics.rb` sha256 + version in both repos (app repo + homebrew tap)
5. Push both repos
6. Sparkle auto-detects via appcast; Homebrew cask is for first-time installs only (`auto_updates true` defers to Sparkle)

## Distribution
- **Sparkle**: EdDSA signed, appcast.xml on GitHub main branch, SUFeedURL in Info.plist via project.yml
- **Homebrew**: `brew install rob-stout/tap/tokenomics` — first install only, Sparkle handles updates
- **Cask sync**: `Casks/tokenomics.rb` in app repo must match `/opt/homebrew/Library/Taps/rob-stout/homebrew-tap/Casks/tokenomics.rb`
- `distribute.sh` compares against last release tag — can't rebuild same version, must bump
- **Mac App Store channel**: separate from the above — "Tokenomics for Safari" (`TokenomicsSafari` + `TokenomicsSafariExtension`) is a sandboxed companion app with no Sparkle; `scripts/distribute-appstore.sh` always validates (archive + local export, no upload) before an explicit `--upload` publishes to App Store Connect

## Code Signing
- Debug builds: `VJKRVGGNXV` (personal team, Apple Development)
- Release builds: `RPDDQP7KZ5` (Developer ID Application, for notarized distribution)
- This split is already configured in `project.yml` under configs

## Portfolio
- Portfolio log: `docs/portfolio-log.md` (Tokenomics-specific, maintained by portfolio-observer agent)
- This is ONE of THREE project-specific portfolio logs — do NOT mix in content from Hopscotch or MARC JSONS
- The other two: `~/projects/hopscotch/docs/portfolio-log.md`, `~/projects/marc-jsons/docs/portfolio-case-study.md`

## Constraints & Gotchas
- `LSUIElement: true` — runs as menu bar agent, no Dock icon
- Reads AI tool credentials from local filesystem (per-provider paths above)
- Bad DMG entries in appcast cause "update error" — always verify DMG contents before release
- Current version: 2.9.0 (build 64)
- Swift strict concurrency: complete
