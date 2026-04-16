import XCTest
import UserNotifications
@testable import Tokenomics

// MARK: - Fake Notification Center

/// Captures `add(_:)` calls from NotificationService without touching the OS.
/// Permission is always granted so `ensurePermission()` returns true immediately.
final class FakeNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {

    // Captured requests — read from the test after triggering evaluate()
    private(set) var addedRequests: [UNNotificationRequest] = []

    // Controls whether requestAuthorization returns granted
    var authorizationGranted: Bool = true

    // MARK: - NotificationCenterProtocol

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func notificationSettings() async -> UNNotificationSettings {
        // Return a settings object that appears "authorized".
        // UNNotificationSettings has no public initializer — we use the
        // notDetermined path deliberately so `ensurePermission` calls
        // `requestAuthorization` which we also control.
        //
        // Because UNNotificationSettings can't be instantiated in tests,
        // we return the real current().notificationSettings() and let
        // `requestAuthorization` handle the permission path.
        await UNUserNotificationCenter.current().notificationSettings()
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        return authorizationGranted
    }
}

// MARK: - Notification Posting Integration Test

/// Verifies that `evaluate()` calls `notificationCenter.add(_:)` with the
/// correct content when a threshold is crossed.
///
/// This catches: "logic decided to notify but forgot to call .add()"
@MainActor
final class NotificationPostingTests: XCTestCase {

    private var fakeCenter: FakeNotificationCenter!
    private var service: NotificationService!

    override func setUp() {
        super.setUp()
        fakeCenter = FakeNotificationCenter()
        fakeCenter.authorizationGranted = true
        service = NotificationService(notificationCenter: fakeCenter)

        // Configure a threshold so the test is deterministic
        SettingsService.setNotificationConfig(
            SettingsService.NotificationConfig(isEnabled: true, threshold: 80),
            for: .claude
        )
        SettingsService.alertWindow = .short
    }

    override func tearDown() {
        // Clean up settings so other tests don't see our threshold
        SettingsService.setNotificationConfig(
            SettingsService.NotificationConfig(isEnabled: false, threshold: 80),
            for: .claude
        )
        super.tearDown()
    }

    // MARK: - Tests

    /// The core test: threshold crossed → fake.add() called with correct content.
    func testEvaluate_thresholdCrossed_callsAddWithCorrectContent() async throws {
        let snapshot = makeSnapshot(utilization: 85)

        service.evaluate(
            providerId: .claude,
            snapshot: snapshot,
            connection: .connected(plan: "Pro")
        )

        // `fireNotification` is async (Task{}), so we need to yield the runloop
        // to let the Task execute before asserting.
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        XCTAssertEqual(fakeCenter.addedRequests.count, 1, "Exactly one notification should have been posted")

        let request = try XCTUnwrap(fakeCenter.addedRequests.first)
        XCTAssertEqual(request.identifier, "claude_short_alert")
        XCTAssertEqual(request.content.title, "Claude Code at 85%")
        XCTAssertEqual(request.content.categoryIdentifier, "USAGE_ALERT")
        XCTAssertNil(request.trigger, "Notification should deliver immediately (no trigger)")
    }

    /// Below threshold → no notification posted
    func testEvaluate_belowThreshold_doesNotCallAdd() async throws {
        service.evaluate(
            providerId: .claude,
            snapshot: makeSnapshot(utilization: 79),
            connection: .connected(plan: "Pro")
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(fakeCenter.addedRequests.count, 0)
    }

    /// Disconnected provider → no notification even at 100%
    func testEvaluate_disconnectedProvider_doesNotCallAdd() async throws {
        service.evaluate(
            providerId: .claude,
            snapshot: makeSnapshot(utilization: 100),
            connection: .authExpired
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(fakeCenter.addedRequests.count, 0)
    }

    // MARK: - Helpers

    private func makeSnapshot(utilization: Double) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "5-Hour Window",
                utilization: utilization,
                resetsAt: Date().addingTimeInterval(3600),
                windowDuration: 5 * 3600
            ),
            longWindow: nil,
            planLabel: "Pro",
            extraUsage: nil,
            creditsBalance: nil
        )
    }
}
