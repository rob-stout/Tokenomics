import XCTest
@testable import Tokenomics

// MARK: - PollingService Tests

final class PollingServiceTests: XCTestCase {

    // MARK: - Initial Tick

    /// start() must fire the action for all registered providers immediately,
    /// not after waiting for the first tickInterval (60s).
    func testStart_firesInitialTickImmediately() async {
        let service = PollingService(idleTimeout: 600)
        await service.registerProvider(.claude, interval: 600)
        await service.registerProvider(.codex, interval: 60)

        var firedIds: [ProviderId] = []
        let expectation = expectation(description: "Both providers tick immediately")
        expectation.expectedFulfillmentCount = 2

        await service.start { id in
            firedIds.append(id)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(firedIds.contains(.claude), "Claude must receive initial tick")
        XCTAssertTrue(firedIds.contains(.codex), "Codex must receive initial tick")

        await service.stop()
    }

    // MARK: - Start idempotency

    /// Calling start() a second time while already running must not create a second loop.
    func testStart_idempotent_doesNotDoubleTickProviders() async {
        let service = PollingService(idleTimeout: 600)
        await service.registerProvider(.claude, interval: 600)

        var tickCount = 0
        let action: @Sendable (ProviderId) async -> Void = { _ in
            tickCount += 1
        }

        await service.start(action: action)
        // Give the initial tick a moment
        try? await Task.sleep(for: .milliseconds(100))
        let countAfterFirstStart = tickCount

        await service.start(action: action) // should be no-op
        try? await Task.sleep(for: .milliseconds(100))

        await service.stop()
        // Second start must not have added more ticks
        XCTAssertEqual(tickCount, countAfterFirstStart,
            "Second start() call must be a no-op when polling is already active")
    }

    // MARK: - isRunning

    func testIsRunning_beforeStart_isFalse() async {
        let service = PollingService()
        let running = await service.isRunning
        XCTAssertFalse(running)
    }

    func testIsRunning_afterStart_isTrue() async {
        let service = PollingService(idleTimeout: 600)
        await service.registerProvider(.claude, interval: 600)
        await service.start { _ in }
        let running = await service.isRunning
        XCTAssertTrue(running)
        await service.stop()
    }

    func testIsRunning_afterStop_isFalse() async {
        let service = PollingService(idleTimeout: 600)
        await service.registerProvider(.claude, interval: 600)
        await service.start { _ in }
        await service.stop()
        let running = await service.isRunning
        XCTAssertFalse(running)
    }

    // MARK: - Provider Schedule

    /// A provider with no lastFetched must report isDue
    func testProviderSchedule_neverFetched_isDue() {
        let schedule = PollingService.ProviderSchedule(interval: 600, lastFetched: nil)
        XCTAssertTrue(schedule.isDue(now: Date()))
    }

    /// A provider fetched just now is NOT due
    func testProviderSchedule_justFetched_isNotDue() {
        let schedule = PollingService.ProviderSchedule(interval: 600, lastFetched: Date())
        XCTAssertFalse(schedule.isDue(now: Date()))
    }

    /// A provider fetched more than interval ago IS due
    func testProviderSchedule_pastInterval_isDue() {
        let lastFetch = Date().addingTimeInterval(-601)
        let schedule = PollingService.ProviderSchedule(interval: 600, lastFetched: lastFetch)
        XCTAssertTrue(schedule.isDue(now: Date()))
    }

    // MARK: - Idle / Wake

    func testIsIdle_initially_notIdle() async {
        // Default idleTimeout is 540s. Right after init, lastActivity = now, so not idle.
        let service = PollingService(idleTimeout: 540)
        let idle = await service.isIdle
        XCTAssertFalse(idle)
    }

    // MARK: - Idle cadence

    /// Idle polling must slow down, not stop: a provider fetched 5 min ago is due on its
    /// own 60s interval but not under the 15 min idle floor.
    func testProviderSchedule_idleFloor_delaysDueness() {
        let fetched = Date().addingTimeInterval(-300)
        let schedule = PollingService.ProviderSchedule(interval: 60, lastFetched: fetched)
        XCTAssertTrue(schedule.isDue(now: Date()))
        XCTAssertFalse(schedule.isDue(now: Date(), idleInterval: 900))
    }

    func testProviderSchedule_idleFloor_dueOnceFloorElapsed() {
        let schedule = PollingService.ProviderSchedule(interval: 60, lastFetched: Date().addingTimeInterval(-901))
        XCTAssertTrue(schedule.isDue(now: Date(), idleInterval: 900))
    }

    /// The idle floor never makes a slow provider poll faster than its own interval.
    func testProviderSchedule_idleFloor_doesNotSpeedUpSlowProvider() {
        let schedule = PollingService.ProviderSchedule(interval: 3600, lastFetched: Date().addingTimeInterval(-1000))
        XCTAssertFalse(schedule.isDue(now: Date(), idleInterval: 900))
    }

    /// Going idle must not end the loop (the old behaviour froze numbers for good).
    func testLoop_staysRunningWhenIdle() async {
        let service = PollingService(idleTimeout: 0, idleInterval: 900)
        await service.registerProvider(.claude, interval: 60)
        await service.start { _ in }
        try? await Task.sleep(for: .milliseconds(100))
        let idle = await service.isIdle
        let running = await service.isRunning
        XCTAssertTrue(idle)
        XCTAssertTrue(running)
        await service.stop()
    }

    // MARK: - Popover-open refresh

    func testClaimStaleProviders_returnsOnlyDueAndMarksThemFetched() async {
        let service = PollingService()
        await service.registerProvider(.claude, interval: 600)
        await service.registerProvider(.codex, interval: 60)
        // Never fetched -> both due on first claim.
        let first = await service.claimStaleProviders()
        XCTAssertEqual(Set(first), [.claude, .codex])
        // Claiming marks them fetched, so an immediate second open fetches nothing.
        let second = await service.claimStaleProviders()
        XCTAssertTrue(second.isEmpty)
        // Later, only the short-interval provider is stale again.
        let later = await service.claimStaleProviders(now: Date().addingTimeInterval(120))
        XCTAssertEqual(later, [.codex])
    }
}
