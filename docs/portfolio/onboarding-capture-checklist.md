# Onboarding screenshot capture — path checklist

Tracks every screen/state in the onboarding flow for portfolio capture, and how
to capture each one. Two routes:

## Route 1 — Xcode previews (recommended)

Every onboarding screen except the connector success screen already has
`#Preview` blocks with staged (fake) states, almost all in light + dark pairs.
Open the file, pick the preview by name, screenshot the canvas.

**Resolution:** set canvas zoom to 100% on a Retina display and a screenshot of
the canvas region is 2x (same pixel density as the live-app captures, which are
1440×1184 for the full 720×592 window). `WindowChromePreview`
(`Views/Onboarding/Components/WindowChromePreview.swift`) wraps a step in the
real 680×580 window layout if you want in-canvas chrome; otherwise capture bare
and add chrome in post.

## Route 2 — live app with faked detection

Debug builds accept a launch argument that fakes what the machine reports
(keychain, `gh` auth, and Cursor data can't be hidden any other way):

```
Tokenomics.app --args -hasCompletedOnboarding NO -tokenomics.demoMode NO -detectionScenario installed
```

- `-detectionScenario installed` — every provider reports "installed, not signed in"
- `-detectionScenario fresh` — every provider reports "not installed"; brand detection returns nothing
- omit the flag for real machine state

Implemented in `Services/DetectionScenario.swift` (guard line at the top of each
provider's `checkConnection()` + a fresh-scenario early-out in
`DetectionService.detect()`). No-op in stable release builds.

## Existing captures (2026-08-28, integration/beta-3 debug build, dark mode)

- `docs/portfolio/onboarding-first-run/` — full flow, real machine state
  (Anthropic/Copilot/Cursor show Connected), 11 shots numbered in flow order
- `docs/portfolio/onboarding-first-run-installed/` — `-detectionScenario installed`
  pass, shots 01–05 (chooser shots 06/06b not captured — window capture broke;
  get them from the ProviderChooserView preview instead)
- Debug-build shots show the orange "Force connect (debug)" footer on connector
  screens — Rob crops/edits in post

## Path inventory

Main guided path: Welcome → Permissions → What-do-you-use (detection) →
Setup plan → connector steps per plan → success → popover.
Side path: "Or set them up one at a time" → Add-a-provider chooser → per-provider
guided flow → back to chooser.

| Screen / state | Preview (file → name) | Live capture |
|---|---|---|
| Welcome | `WelcomeView.swift` → "Welcome — light/dark" | ✅ 01 (both folders) |
| Permissions explainer — initial | `Steps/PermissionsStep.swift` → "Permissions — initial" | ✅ 02 (both folders) |
| Permissions — denied | same file → "Permissions — denied" | — |
| What do you use AI for — detections | `Steps/MultiSelectStep.swift` → "Multi-select — detections" | ✅ 03 (both folders) |
| What do you use AI for — nothing detected | same file → "Multi-select — nothing detected" | — (fresh pass not run) |
| Setup plan — typical | `Steps/SetupPlanStep.swift` → "Setup plan — typical" | ✅ 04 + 04b (both folders; first-run = pre-checked rows, installed = unchecked) |
| Setup plan — single step | same file → "Setup plan — single step" | — |
| Extension install step (Safari copy) | `Steps/ConfirmInstallStep.swift` previews are the CLI variants; Safari copy lives in `BrowserExtensionConnector.installStep(for:)` | ✅ 05 (both folders) |
| Extension connecting (stepper 3) | `Steps/AwaitExtensionView.swift` previews | ✅ 07-extension-connecting (first-run folder) |
| Extension connected (stepper 4, success) | ❌ no preview — success screen is inline in `ConnectorContainer.swift` (the one preview gap) | ✅ 08-extension-connected (first-run folder) |
| Add-a-provider chooser | `ProviderChooserView.swift` → "Provider chooser — light/dark" (fake `providerStates` for any badge mix) | ✅ 06 + 06b (first-run folder only — shows Connected badges from real machine) |
| Install Homebrew / Node / Codex CLI steps | `Steps/ConfirmInstallStep.swift` → three variants × light/dark | — |
| Awaiting external auth (OAuth sign-in) | `Steps/AwaitExternalAuthView.swift` → "Window 5 — Awaiting auth" | — |
| API key paste — empty / ElevenLabs | `Steps/APIKeyPasteStep.swift` → two states × light/dark | — |
| Auto-connect step | `Steps/AutoConnectStep.swift` previews | — |
| Detect step | `Steps/DetectStep.swift` previews | — |
| External-steps preview screen | `Steps/PreviewExternalStepsView.swift` previews | — |
| Stepper component states | `Components/OnboardingStepper.swift` → per-segment previews | (visible in connector shots) |
| First popover after onboarding | n/a (popover, not onboarding) | ✅ 09-first-popover (first-run folder) |

All previews are dark + light; live captures are dark-mode only.
