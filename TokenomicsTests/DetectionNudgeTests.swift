import XCTest
@testable import Tokenomics

/// Regression tests for the non-blocking "we found X on your Mac" detection
/// nudge in the popover. Two pure helpers drive it:
///   - `detectedNotConnectedProviders` — providers installed but not added.
///   - `showsDetectionNudge` — when the banner is allowed to show.
@MainActor
final class DetectionNudgeTests: XCTestCase {

    // MARK: - detectedNotConnectedProviders

    func testReturnsOnlyInstalledNoAuthProviders() {
        let connections: [ProviderId: ProviderConnectionState] = [
            .claude: .connected(plan: "Pro"),
            .cursor: .installedNoAuth,
            .codex: .notInstalled,
        ]
        let result = UsageViewModel.detectedNotConnectedProviders(
            connections: connections,
            order: [.claude, .codex, .cursor]
        )
        XCTAssertEqual(result, [.cursor])
    }

    func testConnectedProvidersAreNotDetectionTargets() {
        let connections: [ProviderId: ProviderConnectionState] = [
            .claude: .connected(plan: "Pro"),
        ]
        XCTAssertTrue(UsageViewModel.detectedNotConnectedProviders(
            connections: connections, order: [.claude]
        ).isEmpty)
    }

    func testAuthExpiredIsNotTreatedAsNewlyDetected() {
        // authExpired is a re-auth case, not "found something new to add".
        let connections: [ProviderId: ProviderConnectionState] = [
            .claude: .authExpired,
        ]
        XCTAssertTrue(UsageViewModel.detectedNotConnectedProviders(
            connections: connections, order: [.claude]
        ).isEmpty)
    }

    func testResultFollowsGivenOrder() {
        let connections: [ProviderId: ProviderConnectionState] = [
            .cursor: .installedNoAuth,
            .codex: .installedNoAuth,
        ]
        let result = UsageViewModel.detectedNotConnectedProviders(
            connections: connections,
            order: [.codex, .cursor]   // codex first
        )
        XCTAssertEqual(result, [.codex, .cursor])
    }

    // MARK: - showsDetectionNudge gating

    func testShowsWhenConnectedAndDetectedAndNotDismissed() {
        XCTAssertTrue(UsageViewModel.showsDetectionNudge(
            dismissed: false, connectedCount: 2, detectedCount: 1
        ))
    }

    func testHiddenWhenNothingConnected() {
        // 0 connected → the full takeover card owns the popover; no overlay nudge.
        XCTAssertFalse(UsageViewModel.showsDetectionNudge(
            dismissed: false, connectedCount: 0, detectedCount: 3
        ))
    }

    func testHiddenWhenNothingNewDetected() {
        XCTAssertFalse(UsageViewModel.showsDetectionNudge(
            dismissed: false, connectedCount: 2, detectedCount: 0
        ))
    }

    func testHiddenAfterDismiss() {
        XCTAssertFalse(UsageViewModel.showsDetectionNudge(
            dismissed: true, connectedCount: 2, detectedCount: 1
        ))
    }
}
