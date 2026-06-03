import XCTest
@testable import Tokenomics

// MARK: - Test doubles

/// Stub WebCompanionStateProvider. Returns either a fresh or stale ExtSideState.
final actor StubWebCompanionService: WebCompanionStateProvider {
    private var state: ExtSideState

    init(state: ExtSideState = .empty) {
        self.state = state
    }

    func currentState() async -> ExtSideState {
        state
    }

    /// Replace the state mid-test to simulate the extension connecting.
    func set(state: ExtSideState) {
        self.state = state
    }
}

/// Stub clock. Records how many times sleep was requested and returns immediately.
/// Allows poll-loop tests to run at full speed without real 5-second waits.
final class StubConnectorClock: ConnectorClock, @unchecked Sendable {
    private(set) var sleepCallCount = 0
    private(set) var lastRequestedSeconds: TimeInterval = 0

    func sleep(seconds: TimeInterval) async throws {
        sleepCallCount += 1
        lastRequestedSeconds = seconds
        // Return immediately — no real sleep. Tests control state transitions directly.
    }
}

/// Stub URL opener. Records the last URL that was opened.
final class StubURLOpener: URLOpener, @unchecked Sendable {
    private(set) var openedURLs: [URL] = []

    @MainActor func open(_ url: URL) {
        openedURLs.append(url)
    }
}

// MARK: - Helpers

extension ExtSideState {
    /// Makes a fresh state (updatedAt = now).
    static func fresh() -> ExtSideState {
        ExtSideState(updatedAt: Date(), snapshots: [:], providerVisibility: [:])
    }

    /// Makes a stale state (updatedAt far in the past).
    static func stale() -> ExtSideState {
        ExtSideState(updatedAt: .distantPast, snapshots: [:], providerVisibility: [:])
    }
}

// MARK: - Tests

final class BrowserExtensionConnectorTests: XCTestCase {

    // MARK: - State 1: Already connected on launch

    /// When the bridge already has a fresh heartbeat, the connector should
    /// immediately emit `.connected` without waiting for any action.
    func testAlreadyConnected_emitsConnectedImmediately() async {
        let stub = StubWebCompanionService(state: .fresh())
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: StubURLOpener()
        )

        let step = await connector.currentStep()

        XCTAssertEqual(step, .connected(plan: ""))
    }

    /// A heartbeat within the 5-minute TTL is fresh. A heartbeat 1 minute ago counts.
    func testFreshnessCheck_withinTTL_isConnected() async {
        // updatedAt = 60 seconds ago — well within the 300s TTL
        let recentDate = Date().addingTimeInterval(-60)
        let state = ExtSideState(updatedAt: recentDate, snapshots: [:], providerVisibility: [:])
        let stub = StubWebCompanionService(state: state)
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: StubURLOpener()
        )

        let step = await connector.currentStep()
        XCTAssertEqual(step, .connected(plan: ""))
    }

    /// A heartbeat just beyond 300s is stale — connector should show needsAction.
    func testFreshnessCheck_beyondTTL_showsInstallStep() async {
        // A stale heartbeat (beyond TTL) means the extension isn't connected, so
        // the connector starts at the install step (`.confirmingInstall`).
        let staleDate = Date().addingTimeInterval(-301)
        let state = ExtSideState(updatedAt: staleDate, snapshots: [:], providerVisibility: [:])
        let stub = StubWebCompanionService(state: state)
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: StubURLOpener()
        )

        let step = await connector.currentStep()
        guard case .confirmingInstall = step else {
            return XCTFail("Expected .confirmingInstall, got \(step)")
        }
    }

    // MARK: - State 2: Not connected — install step

    /// When the bridge state is stale, `currentStep()` shows the install step.
    func testNotConnected_showsInstallStep() async {
        let stub = StubWebCompanionService(state: .stale())
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: StubURLOpener()
        )

        let step = await connector.currentStep()
        guard case .confirmingInstall = step else {
            return XCTFail("Expected .confirmingInstall, got \(step)")
        }
    }

    /// Tapping the primary CTA should open the Chrome Web Store URL.
    func testPerformPrimaryAction_opensWebStoreURL() async {
        let stub = StubWebCompanionService(state: .stale())
        let opener = StubURLOpener()
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: opener
        )

        await connector.performPrimaryAction()

        let expected = URL(string: "https://chromewebstore.google.com/detail/gcjaebikgcbccgbnbcimccflcgoeefio")!
        XCTAssertEqual(opener.openedURLs.last, expected)
    }

    /// The Web Store URL should use the dev-keypair extension ID, not a placeholder.
    func testWebStoreURL_containsCorrectExtensionID() async {
        let stub = StubWebCompanionService(state: .stale())
        let opener = StubURLOpener()
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: opener
        )

        await connector.performPrimaryAction()

        XCTAssertTrue(
            opener.openedURLs.last?.absoluteString.contains("gcjaebikgcbccgbnbcimccflcgoeefio") == true,
            "Web Store URL must include the extension's dev-keypair ID"
        )
    }

    /// Tapping primary action twice should NOT open the URL a second time —
    /// the connector is already in `.polling` phase.
    func testPerformPrimaryAction_idempotent_doesNotDoubleOpen() async {
        let stub = StubWebCompanionService(state: .stale())
        let opener = StubURLOpener()
        let clock = StubConnectorClock()
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: clock,
            opener: opener
        )

        await connector.performPrimaryAction()
        await connector.performPrimaryAction()

        XCTAssertEqual(opener.openedURLs.count, 1, "URL should only be opened once")
    }

    // MARK: - State 2 continued: Poll transitions to connected

    /// Once the store is opened and the bridge connects, `currentStep()` should
    /// return `.connected`. This tests the transition inside the polling phase.
    func testBridgeConnects_duringPollingPhase_transitionsToConnected() async {
        let stub = StubWebCompanionService(state: .stale())
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: StubURLOpener()
        )

        // Open the store — puts connector into .polling
        await connector.performPrimaryAction()

        // Simulate the extension sending a heartbeat
        await stub.set(state: .fresh())

        // Next poll should detect the fresh heartbeat
        let step = await connector.currentStep()
        XCTAssertEqual(step, .connected(plan: ""))
    }

    /// The poll interval should be approximately 5 seconds.
    /// We verify the clock was asked to sleep with the right duration.
    func testPollCadence_requests5SecondSleep() async throws {
        let stub = StubWebCompanionService(state: .stale())
        let clock = StubConnectorClock()
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: clock,
            opener: StubURLOpener()
        )

        // Trigger polling — this starts the background poll loop
        await connector.performPrimaryAction()

        // Give the Task a moment to enter the sleep call
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Cancel so the loop exits
        await connector.cancel()

        XCTAssertEqual(
            clock.lastRequestedSeconds, 5.0,
            accuracy: 0.001,
            "Poll loop should request 5-second sleeps"
        )
    }

    // MARK: - State 3: User skips

    /// Tapping skip transitions the connector to `.skipped`.
    func testSkip_emitsSkipped() async {
        let stub = StubWebCompanionService(state: .stale())
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: StubURLOpener()
        )

        await connector.skip()

        let step = await connector.currentStep()
        XCTAssertEqual(step, .skipped)
    }

    /// Skip works even after the store has been opened (polling phase).
    func testSkip_whilePolling_emitsSkipped() async {
        let stub = StubWebCompanionService(state: .stale())
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: StubURLOpener()
        )

        await connector.performPrimaryAction() // → polling
        await connector.skip()

        let step = await connector.currentStep()
        XCTAssertEqual(step, .skipped)
    }

    // MARK: - Cancel

    /// `cancel()` resets the connector to its initial state so it can be re-used.
    func testCancel_resetsToNone_showsInstallStep() async {
        let stub = StubWebCompanionService(state: .stale())
        let connector = BrowserExtensionConnector(
            webCompanion: stub,
            clock: StubConnectorClock(),
            opener: StubURLOpener()
        )

        await connector.performPrimaryAction() // → polling
        await connector.cancel()              // → none

        // Back to the start of the flow: the install step, not a connecting screen.
        let step = await connector.currentStep()
        guard case .confirmingInstall = step else {
            return XCTFail("Expected .confirmingInstall after cancel, got \(step)")
        }
    }

    // MARK: - isFresh helper tests

    func testIsFresh_distantPast_returnsFalse() {
        XCTAssertFalse(ExtSideState.empty.isFresh())
    }

    func testIsFresh_now_returnsTrue() {
        XCTAssertTrue(ExtSideState.fresh().isFresh())
    }

    func testIsFresh_boundary_returnsTrue() {
        // updatedAt = 250 seconds ago, window = 300 → still inside the window
        let withinBoundary = Date().addingTimeInterval(-250)
        let state = ExtSideState(updatedAt: withinBoundary, snapshots: [:], providerVisibility: [:])
        XCTAssertTrue(state.isFresh(within: 300))
    }

    func testIsFresh_customWindow_respectsParameter() {
        let tenSecondsAgo = Date().addingTimeInterval(-10)
        let state = ExtSideState(updatedAt: tenSecondsAgo, snapshots: [:], providerVisibility: [:])
        XCTAssertTrue(state.isFresh(within: 60))   // 10s ago < 60s window → fresh
        XCTAssertFalse(state.isFresh(within: 5))   // 10s ago > 5s window → stale
    }
}
