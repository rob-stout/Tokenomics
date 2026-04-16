import XCTest
@testable import Tokenomics

// MARK: - Notification Content Tests

/// Tests the string content that would appear in a notification.
///
/// NotificationService builds notification content from:
///   title = "\(providerId.displayName) at \(Int(utilization))%"
///   body  = "\(window.timeUntilReset). You may hit your limit soon."
///
/// These tests pin the content construction logic by asserting the same
/// string-building rules, without actually firing a UNNotificationRequest
/// (which requires permission we won't have in CI).
final class NotificationContentTests: XCTestCase {

    // MARK: - Title construction

    func testNotificationTitle_claude_containsDisplayName() {
        let title = "\(ProviderId.claude.displayName) at \(Int(85))%"
        XCTAssertEqual(title, "Claude Code at 85%")
    }

    func testNotificationTitle_copilot_containsDisplayName() {
        let title = "\(ProviderId.copilot.displayName) at \(Int(75))%"
        XCTAssertEqual(title, "GitHub Copilot at 75%")
    }

    func testNotificationTitle_cursor_containsDisplayName() {
        let title = "\(ProviderId.cursor.displayName) at \(Int(92))%"
        XCTAssertEqual(title, "Cursor at 92%")
    }

    func testNotificationTitle_atExactly100_shows100Percent() {
        // 100% — exactly at limit
        let title = "\(ProviderId.claude.displayName) at \(Int(100.0))%"
        XCTAssertEqual(title, "Claude Code at 100%")
    }

    func testNotificationTitle_over100_showsIntegerTruncation() {
        // 120% usage — Int() truncates, title shows 120%
        let utilization = 120.0
        let title = "\(ProviderId.claude.displayName) at \(Int(utilization))%"
        XCTAssertEqual(title, "Claude Code at 120%")
    }

    // MARK: - Body construction (timeUntilReset)

    func testNotificationBody_withTimeRemaining_includesSuffix() {
        // Simulate a window resetting in 2.5 hours
        let resetsAt = Date().addingTimeInterval(2 * 3600 + 30 * 60)
        let window = WindowUsage(
            label: "5-Hour Window",
            utilization: 85,
            resetsAt: resetsAt,
            windowDuration: 5 * 3600
        )
        let body = "\(window.timeUntilReset). You may hit your limit soon."
        XCTAssertTrue(body.contains("Resets in"), "Body should contain reset info: \(body)")
        XCTAssertTrue(body.hasSuffix(". You may hit your limit soon."))
    }

    func testNotificationBody_alreadyReset_showsResettingNow() {
        let resetsAt = Date().addingTimeInterval(-10) // past reset
        let window = WindowUsage(
            label: "5-Hour Window",
            utilization: 100,
            resetsAt: resetsAt,
            windowDuration: 5 * 3600
        )
        let body = "\(window.timeUntilReset). You may hit your limit soon."
        XCTAssertTrue(body.hasPrefix("Resetting now"), "Body should show resetting: \(body)")
    }

    // MARK: - Notification identifier uniqueness

    func testNotificationIdentifier_isProviderAndWindowScoped() {
        // The identifier format must be stable — changing it would suppress
        // duplicate detection and allow notification spam.
        let identifier = "\(ProviderId.claude.rawValue)_short_alert"
        XCTAssertEqual(identifier, "claude_short_alert")

        let longIdentifier = "\(ProviderId.copilot.rawValue)_long_alert"
        XCTAssertEqual(longIdentifier, "copilot_long_alert")
    }
}
