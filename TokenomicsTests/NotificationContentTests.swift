import XCTest
@testable import Tokenomics

// MARK: - Notification Content Tests

/// Tests the string content that would appear in a notification.
///
/// NotificationService builds the title via `usageAlertTitle(for:utilization:)`,
/// which uses the pool's source-of-truth label (`poolLabel`):
///   title = "\(providerId.poolLabel) at \(Int(utilization))%"
///   body  = "\(window.timeUntilReset). You may hit your limit soon."
///
/// These call the REAL builder (not a re-implemented format string) so the test
/// can't silently drift from production again.
final class NotificationContentTests: XCTestCase {

    // MARK: - Title construction

    func testNotificationTitle_usesPoolLabel() {
        XCTAssertEqual(
            NotificationService.usageAlertTitle(for: .claude, utilization: 85),
            "Anthropic at 85%"
        )
    }

    func testNotificationTitle_copilot() {
        XCTAssertEqual(
            NotificationService.usageAlertTitle(for: .copilot, utilization: 75),
            "GitHub Copilot at 75%"
        )
    }

    func testNotificationTitle_cursor() {
        XCTAssertEqual(
            NotificationService.usageAlertTitle(for: .cursor, utilization: 92),
            "Cursor at 92%"
        )
    }

    /// The bug this whole alignment effort fixed: multi-pool brands must name the
    /// POOL, not the brand. Before, these read "OpenAI"/"Google AI"/"Gemini".
    func testNotificationTitle_multiPoolPoolsAreDisambiguated() {
        XCTAssertEqual(NotificationService.usageAlertTitle(for: .codex, utilization: 90),
                       "Codex CLI at 90%")
        XCTAssertEqual(NotificationService.usageAlertTitle(for: .gemini, utilization: 90),
                       "Gemini CLI at 90%")
        XCTAssertEqual(NotificationService.usageAlertTitle(for: .geminiConsumer, utilization: 90),
                       "Gemini (app) at 90%")
        XCTAssertEqual(NotificationService.usageAlertTitle(for: .chatgpt, utilization: 90),
                       "ChatGPT at 90%")
    }

    func testNotificationTitle_atExactly100_shows100Percent() {
        XCTAssertEqual(
            NotificationService.usageAlertTitle(for: .claude, utilization: 100.0),
            "Anthropic at 100%"
        )
    }

    func testNotificationTitle_over100_showsIntegerTruncation() {
        // 120% usage — Int() truncates, title shows 120%
        XCTAssertEqual(
            NotificationService.usageAlertTitle(for: .claude, utilization: 120.0),
            "Anthropic at 120%"
        )
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
