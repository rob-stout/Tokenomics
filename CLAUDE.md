# Tokenomics

macOS menu bar app that shows AI coding tool usage at a glance.
Supports Claude Code, Codex CLI, and Gemini CLI.

## Tech Stack
- **UI**: SwiftUI (macOS 13+)
- **Architecture**: MVVM with @Observable
- **Updates**: Sparkle framework (auto-update via appcast.xml)
- **Distribution**: Developer ID signed .dmg, hosted on GitHub Releases
- **Build config**: xcodegen (`project.yml` → Xcode project)

## Project Structure
```
Tokenomics/
├── App/           # App entry point, menu bar setup
├── Models/        # Data models
├── Views/         # SwiftUI views (popover, settings)
├── ViewModels/    # @Observable view models
├── Services/      # API clients, credential readers
└── Resources/     # Assets, Info.plist, entitlements
```

## Commands
```bash
xcodegen generate    # Regenerate Xcode project from project.yml
# Build/run via Xcode — menu bar app (LSUIElement = true, no dock icon)
```

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
- Reads AI tool credentials from local filesystem (~/.claude/, ~/.codex/, ~/.gemini/)
- Sparkle update feed: appcast.xml on GitHub main branch
- Current version: 2.2.6 (build 15)
- Swift strict concurrency: complete
