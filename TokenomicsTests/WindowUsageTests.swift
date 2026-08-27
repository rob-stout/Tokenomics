import XCTest
@testable import Tokenomics

// MARK: - WindowUsage Reset-Time Sublabel Tests
//
// Regression coverage for the "Resets Sunday" bug: Anthropic (and other APIs)
// return a nil resetsAt for windows with no active reset cycle yet (e.g. zero
// usage). Providers map that to `.distantFuture` as a pace sentinel — but
// `.distantFuture` (Jan 1, 4001) happens to fall on a Sunday, so any window
// built with that sentinel and no sublabelOverride would silently format a
// fabricated weekday instead of admitting there's no active session.

final class WindowUsageTests: XCTestCase {

    // MARK: - Neutral Sublabel on Nil resetsAt

    /// Mirrors ClaudeProvider's fix: 5-hour window with no active session.
    func testTimeUntilReset_fiveHourNilResetsAt_showsNoActiveSession() {
        let window = WindowUsage(
            label: "5-Hour Window",
            utilization: 0,
            resetsAt: .distantFuture,
            windowDuration: 5 * 3600,
            sublabelOverride: "No active session"
        )
        XCTAssertEqual(window.timeUntilReset, "No active session")
    }

    /// Mirrors ClaudeProvider's fix: 7-day window with no usage yet (e.g. a
    /// fresh account, or `seven_day_sonnet` before any Sonnet usage).
    func testTimeUntilReset_sevenDayNilResetsAt_showsNoUsageYet() {
        let window = WindowUsage(
            label: "7-Day Window",
            utilization: 0,
            resetsAt: .distantFuture,
            windowDuration: 7 * 24 * 3600,
            sublabelOverride: "No usage yet"
        )
        XCTAssertEqual(window.timeUntilReset, "No usage yet")
    }

    // MARK: - Regression: distantFuture Must Never Reach the User as a Weekday

    /// Documents the exact bug this fix prevents. A WindowUsage built with the
    /// distantFuture sentinel and NO override formats it as a real calendar
    /// weekday — this is the shape every provider must avoid shipping when its
    /// API's resetsAt comes back nil.
    func testTimeUntilReset_distantFutureWithoutOverride_isTheBugThisFixPrevents() {
        let window = WindowUsage(
            label: "5-Hour Window",
            utilization: 0,
            resetsAt: .distantFuture,
            windowDuration: 5 * 3600
        )
        XCTAssertEqual(window.timeUntilReset, "Resets Sunday",
            "distantFuture formats as Sunday — this is why every nil-resetsAt window must set sublabelOverride")
    }

    /// With the override in place, no weekday name can leak into the sublabel —
    /// no matter what day distantFuture (or any future sentinel) resolves to.
    func testTimeUntilReset_withOverride_neverContainsAWeekday() {
        let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let window = WindowUsage(
            label: "5-Hour Window",
            utilization: 0,
            resetsAt: .distantFuture,
            windowDuration: 5 * 3600,
            sublabelOverride: "No active session"
        )
        for weekday in weekdays {
            XCTAssertFalse(window.timeUntilReset.contains(weekday),
                "sublabelOverride must fully replace the date-formatted text, found \(weekday)")
        }
    }

    // MARK: - Pace Stays Honest for the Sentinel Case

    /// Even though resetsAt is a sentinel (not a real reset time), pace must
    /// still read 0 — there's no progress through a window that isn't active.
    func testPace_distantFutureSentinel_isZero() {
        let window = WindowUsage(
            label: "5-Hour Window",
            utilization: 0,
            resetsAt: .distantFuture,
            windowDuration: 5 * 3600,
            sublabelOverride: "No active session"
        )
        XCTAssertEqual(window.pace, 0)
    }

    // MARK: - Real Reset Times Still Render Correctly (No Regression)

    /// A genuine reset time under 24h away must still show hours/minutes, not
    /// get swallowed by the neutral-sublabel fix.
    func testTimeUntilReset_realResetWithinHours_showsCountdown() {
        let window = WindowUsage(
            label: "5-Hour Window",
            utilization: 42,
            // +5s buffer so the Int() truncation in timeUntilReset can't floor
            // the elapsed-since-construction gap below the 15-minute mark.
            resetsAt: Date().addingTimeInterval(2 * 3600 + 15 * 60 + 5),
            windowDuration: 5 * 3600
        )
        XCTAssertEqual(window.timeUntilReset, "Resets in 2h 15m")
    }

    /// A genuine reset time 24h+ away (real weekly window) must still show the
    /// weekday — only the fabricated sentinel case is suppressed.
    func testTimeUntilReset_realResetDaysAway_showsWeekday() {
        let window = WindowUsage(
            label: "7-Day Window",
            utilization: 10,
            resetsAt: Date().addingTimeInterval(3 * 24 * 3600),
            windowDuration: 7 * 24 * 3600
        )
        XCTAssertTrue(window.timeUntilReset.hasPrefix("Resets "))
        XCTAssertNotEqual(window.timeUntilReset, "Resets today")
        XCTAssertNotEqual(window.timeUntilReset, "Resets tomorrow")
    }
}
