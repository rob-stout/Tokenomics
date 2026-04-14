# Tokenomics — Testing Guide

## Running Tests

```bash
# Full test run (via xcodebuild)
xcodebuild test -scheme Tokenomics -destination 'platform=macOS'

# Pre-PR gate (regenerates project + build + test)
./scripts/pre-pr-check.sh
```

Tests also run inside Xcode via Product → Test (Cmd+U) or the test navigator.

## Test Suite Overview

**35 tests across 6 files — all critical-path, no fluff.**

| File | Module | Tests |
|---|---|---|
| `UsageDataTests.swift` | `UsageData`, `ExtraUsage` | Plan inference (all 3 branches), dollar formatting, ISO8601 date decoding |
| `UsageServiceTests.swift` | `UsageService`, `AppError` | Backoff math, exponential progression, 1h cap, error classification |
| `NotificationServiceTests.swift` | `NotificationService` | Hysteresis state machine (idle→alerted→idle), per-provider isolation, disabled config, disconnected provider |
| `SettingsServiceTests.swift` | `SettingsService` | Smart mode, pin toggle, provider order, notification config round-trips, alert window |
| `PollingServiceTests.swift` | `PollingService`, `ProviderSchedule` | Initial tick fires immediately, start idempotency, isRunning, schedule due-date math, idle state |
| `ClaudeProviderTests.swift` | `ClaudeProvider` | Token rotation detection logic (3 branches), plan label mapping |
| `ProviderTests.swift` | `Provider`, `AppError` | Identity, display labels, short label uniqueness, connection state, error descriptions |

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

## What's Deliberately Skipped

| Module | Reason |
|---|---|
| `UpdaterService.swift` | Sparkle delegate — integration-level, depends on `SPUStandardUserDriverDelegate` lifecycle that doesn't run headlessly. Test via manual TestFlight builds. |
| `KeychainService.swift` | Wraps Apple's Security framework. Mocking `SecItemCopyMatching` via swizzling isn't worth the fragility at this scale. ClaudeProvider's token-rotation logic is covered by logic-level tests instead. |
| `Widget extension rendering` | `TokenomicsWidgetEntryView` is visual — correctness is tested by eyeballing on a real device. Widget data store (`WidgetDataStore`) reads from App Group UserDefaults; covered indirectly by SettingsService tests. |
| `ActivityMonitor.swift` | Wraps `NSWorkspace` event observation — no testable pure logic surface. |
| `LaunchAtLoginService.swift` | Thin wrapper over `SMAppService`. Tested at the OS level during QA. |

## Architecture Notes for Tests

- **No network calls**: `UsageService` tests validate backoff math directly (the actor's state is isolated; a future refactor could inject a `URLSession` to enable full mock-network tests via `MockURLProtocol`, which is already stubbed in `UsageServiceTests.swift`).
- **No keychain access**: Token-rotation detection is extracted to pure conditional logic in `ClaudeProviderTests`.
- **UserDefaults isolation**: `SettingsServiceTests` cleans up all touched keys in `tearDown()` to prevent cross-test contamination.
- **Swift 6 strict concurrency**: All tests compile with `SWIFT_STRICT_CONCURRENCY: complete`. `NotificationServiceTests` is `@MainActor` to match the service.
