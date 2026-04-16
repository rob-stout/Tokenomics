# Tokenomics — Testing Guide

## Running Tests

```bash
# Unit tests (fast, no entitlements required)
xcodebuild test -scheme Tokenomics -destination 'platform=macOS'

# Integration tests (requires App Group entitlement for widget sync)
xcodebuild test -scheme TokenomicsIntegration -destination 'platform=macOS'

# Pre-PR gate (regenerates project + build + both test suites)
./scripts/pre-pr-check.sh

# Skip integration phase (CI without App Group entitlements)
SKIP_INTEGRATION=1 ./scripts/pre-pr-check.sh
```

Tests also run inside Xcode via Product → Test (Cmd+U) or the test navigator.
Select the **Tokenomics** or **TokenomicsIntegration** scheme before running.

## Test Suite Overview

### TokenomicsTests (unit tests) — 161 tests across 12 files

| File | Module | Tests |
|---|---|---|
| `UsageDataTests.swift` | `UsageData`, `ExtraUsage` | Plan inference (all 3 branches), dollar formatting, ISO8601 date decoding |
| `UsageServiceTests.swift` | `UsageService`, `AppError` | Backoff math, exponential progression, 1h cap, error classification |
| `NotificationServiceTests.swift` | `NotificationService` | Hysteresis state machine (idle→alerted→idle), per-provider isolation, disabled config, disconnected provider |
| `SettingsServiceTests.swift` | `SettingsService` | Smart mode, pin toggle, provider order, notification config round-trips, alert window |
| `PollingServiceTests.swift` | `PollingService`, `ProviderSchedule` | Initial tick fires immediately, start idempotency, isRunning, schedule due-date math, idle state |
| `ClaudeProviderTests.swift` | `ClaudeProvider` | Token rotation detection logic (3 branches), plan label mapping |
| `ProviderTests.swift` | `Provider`, `AppError` | Identity, display labels, short label uniqueness, connection state, error descriptions |
| `UsageStateTests.swift` | `UsageState` | Threshold boundary pinning (70/90/100) for caution/warning/depleted |
| `TrackingBarMathTests.swift` | `WindowUsage.pace`, bar fill | Clamp math (0%, 50%, 100%, >100%, negative), pace at start/midpoint/end, zero-duration windows |
| `NotificationContentTests.swift` | `NotificationService` content | Title/body string construction per provider, 100%/120% edge cases, identifier format |
| `ProviderParsingTests.swift` | All providers except Claude | Fixture-based JSON/JSONL decode tests for Codex, Cursor, Copilot, Runway, ElevenLabs, Gemini |
| `WidgetThemeTests.swift` | `WidgetTheme` | Widget color token pinning — see "Widget theme pinning" section below |

### Widget theme pinning

`WidgetThemeTests.swift` pins every color token in every `WidgetTheme` preset so an accidental change to any RGB value, opacity, or gradient stop location causes an immediate test failure.

**Why it's needed:** Widget color tokens have been accidentally overwritten during refactors. Visual regression only surfaces after a build to a real device. These tests catch it at the unit-test level.

**Presets covered:**

| Preset | Role |
|---|---|
| `.dark` | Full-color branded dark background |
| `.light` | Full-color branded light background |
| `.accented` | Retired system-semantic preset — structural properties pinned (opacities, iconSuffix, empty gradient) |

**Token coverage per preset (`.dark` and `.light`):**
- `labelColor` — RGB + alpha
- `shortColor` — RGB + alpha
- `longColor` — RGB + alpha
- `barTrack` — RGB + alpha
- `barFillOpacity` — scalar
- `iconSuffix` — string
- `paceDotColor` — RGB + alpha
- `gradientStops` — count, per-stop location, per-stop RGB + alpha

**Resolver tests:** `WidgetTheme.current(for:renderingMode:)` is tested for all six `(ColorScheme × WidgetRenderingMode)` combinations (`.dark`/`.light` × `.fullColor`/`.accented`/`.vibrant`). The resolver intentionally ignores `renderingMode` and keys only on `ColorScheme` — these tests enforce that contract.

**Fill color tests:** `fillColor(for:isLong:)` is tested at 0%, 100%, and 150% utilization, for both `isLong: false` (returns `shortColor`) and `isLong: true` (returns `longColor`), plus a default parameter test.

**Color comparison approach:** SwiftUI `Color` doesn't implement meaningful `Equatable` for custom colors. Each color is resolved to `NSColor` in the sRGB color space via `NSColor(swiftUIColor).usingColorSpace(.sRGB)`, then individual RGBA components are compared with `accuracy: 0.0001` (~0.025 out of 255 — well below any perceptible change).

### TokenomicsIntegrationTests — 8 tests across 2 files

| File | Module | Tests |
|---|---|---|
| `NotificationPostingTests.swift` | `NotificationService` + seam | `add()` called with correct content on threshold cross; not called below threshold or when disconnected |
| `WidgetSyncTests.swift` | `WidgetDataStore` | Roundtrip write→read equality; multi-provider; second write replaces first; Sparkle relaunch persistence |

### Provider Fixtures (`TokenomicsTests/Fixtures/`)

| File | Provider | Covers |
|---|---|---|
| `codex_session_typical.jsonl` | Codex | rate_limits + token_count, plan_type=pro |
| `codex_session_missing_rate_limits.jsonl` | Codex | token_count only (no rate_limits) |
| `codex_session_missing_token_count.jsonl` | Codex | rate_limits only (no token_count) |
| `codex_session_unknown_fields.jsonl` | Codex | Forward compat: extra fields ignored |
| `cursor_usage_pro.json` | Cursor | Pro plan, server-computed percent |
| `cursor_usage_free.json` | Cursor | Free plan, autoModelSelectedDisplayMessage |
| `cursor_usage_missing_fields.json` | Cursor | Null individualUsage graceful fallback |
| `copilot_user_free.json` | Copilot | Free SKU, limited quotas |
| `copilot_user_individual.json` | Copilot | Individual SKU, null quotas |
| `copilot_user_unknown_sku.json` | Copilot | Unknown SKU → copilotPlan fallback |
| `runway_credits_typical.json` | Runway | Credits with reset date |
| `runway_credits_no_reset.json` | Runway | Credits with null resets_at |
| `elevenlabs_subscription_creator.json` | ElevenLabs | Creator tier, Unix reset |
| `elevenlabs_subscription_free.json` | ElevenLabs | Free tier, null reset |
| `elevenlabs_subscription_missing_tier.json` | ElevenLabs | Missing tier → "Free" fallback |
| `gemini_session_typical.json` | Gemini | Two gemini messages with tokens |
| `gemini_session_no_tokens.json` | Gemini | Gemini message with null tokens |

## Regression Tests (Mandatory)

These tests were written to catch specific past bugs. If any of these fail, do not merge.

| Test | Regression |
|---|---|
| `testRateLimitBackoff_firstHit_enforces5MinMinimum` | commit 111540c — `retry-after: 0` must enforce 5-min minimum |
| `testRateLimitBackoff_cappedAt1Hour` | Backoff must not grow unbounded |
| `testPlanInference_extraUsage_returnsMax` | Max plan detection via `extra_usage` field |
| `testPlanInference_sevenDayOpus_returnsPro` | Pro plan detection via per-model breakdown |
| `testPlanInference_noExtras_returnsFree` | Free plan fallback |
| `testHysteresis_noRearmAboveFloor` | No re-alert until 10% drop below threshold |
| `testHysteresis_belowFloor_rearmsForNextCrossing` | Re-arm works after sufficient drop |
| `testSmartMode_emptyPinnedSet_isActive` | Empty pinned set = smart (worst-of-N) mode |
| `testStart_firesInitialTickImmediately` | Initial tick fires on start, not after first interval |
| `testTokenRotation_differentToken_triggersClear` | Token rotation clears rate-limit backoff |
| `testSparkleRelaunch_dataPersistedAcrossReads` | Widget data survives Sparkle post-install relaunch (commit d5cee6d regression) |
| `testEvaluate_thresholdCrossed_callsAddWithCorrectContent` | `fireNotification` actually calls `.add()` — production code path, not just state machine |

## Production Seams Added

| Seam | File | Rationale |
|---|---|---|
| `NotificationCenterProtocol` | `NotificationService.swift` | Minimal protocol over `UNUserNotificationCenter` — allows injecting `FakeNotificationCenter` in integration tests without touching the OS notification system. `UNUserNotificationCenter` conforms via extension. `NotificationService.init(notificationCenter:)` defaults to `UNUserNotificationCenter.current()` — zero behavior change in production. |

## What's Deliberately Skipped

| Module | Reason |
|---|---|
| `UpdaterService.swift` | Sparkle delegate — integration-level, depends on `SPUStandardUserDriverDelegate` lifecycle that doesn't run headlessly. Test via manual TestFlight builds. |
| `KeychainService.swift` | Wraps Apple's Security framework. Mocking `SecItemCopyMatching` via swizzling isn't worth the fragility at this scale. ClaudeProvider's token-rotation logic is covered by logic-level tests instead. |
| `Widget extension rendering` | `TokenomicsWidgetEntryView` is visual — correctness is tested by eyeballing on a real device. |
| `ActivityMonitor.swift` | Wraps `NSWorkspace` event observation — no testable pure logic surface. |
| `LaunchAtLoginService.swift` | Thin wrapper over `SMAppService`. Tested at the OS level during QA. |
| `UsageState.color` and `MenuBarRingsView` CGColor alphas | These are view-layer colors (orange/red for state, white for bar fill) tied directly to SwiftUI/AppKit rendering. Pinning them would couple tests to SwiftUI internals without adding meaningful behavioral coverage — verified visually. Widget theme color tokens are covered separately in `WidgetThemeTests.swift`. |
| StableDiffusionProvider parsing | `BalanceHistory` is private and depends on `UserDefaults.standard` (hard to isolate without test-specific key injection). Balance math is a simple single-field decode. Covered manually. |
| Midjourney, Suno, Udio providers | Placeholder providers listed for future support, not yet implemented (coming soon). They have no API integration and no parsing logic — there is nothing to test yet. |

## Architecture Notes for Tests

- **No network calls**: All provider tests use local fixture files. Network paths are tested only indirectly via the state-machine and content-construction tests.
- **No keychain access**: Token-rotation detection is extracted to pure conditional logic in `ClaudeProviderTests`.
- **UserDefaults isolation**: `SettingsServiceTests` cleans up all touched keys in `tearDown()` to prevent cross-test contamination.
- **Swift 6 strict concurrency**: All tests compile with `SWIFT_STRICT_CONCURRENCY: complete`. `NotificationServiceTests` and `NotificationPostingTests` are `@MainActor` to match the service.
- **Widget sync in CI**: `WidgetSyncTests` uses `appGroupAvailable` guard — tests skip gracefully when the App Group container isn't provisioned (CI without entitlements). They pass locally with a signed debug build.
- **Codex JSONL parsing**: Tests decode individual JSONL lines via mirror structs (the event wrappers `CodexSessionEvent`/`CodexTokenCountEvent` are private). `CodexRateLimits`, `CodexTokenCount`, `CodexRateLimitWindow`, and `CodexCredits` are internal and tested directly via `@testable`.
