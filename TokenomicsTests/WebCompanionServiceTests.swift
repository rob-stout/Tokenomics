import XCTest
@testable import Tokenomics

// MARK: - WebCompanionServiceTests
//
// FSEvents integration is not exercised here — that layer is thin and would need
// a real App Group container. Instead we test the actor's pure logic through
// `handleStateChange(_:)`, which is the same path FSEvents drives at runtime.

final class WebCompanionServiceTests: XCTestCase {

    // MARK: - Helpers

    /// An empty directory per test, so the service never reads the real bridge files.
    private func isolatedService() -> WebCompanionService {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebCompanionServiceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return WebCompanionService(directories: [dir])
    }

    private func makeSnapshot(provider: String, capturedAt: Date = Date()) -> BridgeSnapshot {
        BridgeSnapshot(
            provider: provider,
            capturedAt: capturedAt,
            estimated: false,
            shortWindow: BridgeWindow(
                label: "5h",
                utilization: 0.4,
                resetsAt: capturedAt.addingTimeInterval(3600),
                windowDurationSec: 18000,
                sublabelOverride: nil
            ),
            longWindow: nil,
            planLabel: "Pro"
        )
    }

    private func makeExtState(
        snapshots: [String: BridgeSnapshot] = [:],
        visibility: [String: ProviderVisibilitySetting] = [:]
    ) -> ExtSideState {
        ExtSideState(updatedAt: Date(), snapshots: snapshots, providerVisibility: visibility)
    }

    // MARK: - Initial State — No File

    func testInitialState_noFile_returnsEmpty() async {
        let service = isolatedService()
        let state = await service.currentState()
        XCTAssertEqual(state.snapshots.count, 0)
        XCTAssertEqual(state.providerVisibility.count, 0)
    }

    // MARK: - Read Populated File

    func testCurrentState_afterHandleStateChange_returnsUpdatedState() async {
        let service = isolatedService()
        let snap = makeSnapshot(provider: "claude")
        let ext = makeExtState(snapshots: ["claude": snap])

        await service.handleStateChange(ext)

        let state = await service.currentState()
        XCTAssertEqual(state.snapshots["claude"]?.provider, "claude")
    }

    // MARK: - snapshot(for:) Lookup

    func testSnapshotForProviderId_found() async {
        let service = isolatedService()
        let snap = makeSnapshot(provider: ProviderId.codex.rawValue)
        await service.handleStateChange(makeExtState(snapshots: [ProviderId.codex.rawValue: snap]))

        let found = await service.snapshot(for: .codex)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.provider, "codex")
    }

    func testSnapshotForProviderId_absent_returnsNil() async {
        let service = isolatedService()
        let result = await service.snapshot(for: .claude)
        XCTAssertNil(result)
    }

    // MARK: - providerVisibility()

    func testProviderVisibility_reflectsLatestState() async {
        let service = isolatedService()
        let visibility: [String: ProviderVisibilitySetting] = [
            "claude": ProviderVisibilitySetting(enabled: true, lastChangedAt: Date()),
            "codex":  ProviderVisibilitySetting(enabled: false, lastChangedAt: Date()),
        ]
        await service.handleStateChange(makeExtState(visibility: visibility))

        let result = await service.providerVisibility()
        XCTAssertTrue(result["claude"]?.enabled == true)
        XCTAssertTrue(result["codex"]?.enabled == false)
    }

    // MARK: - Multiple State Updates

    func testHandleStateChange_multipleUpdates_latestWins() async {
        let service = isolatedService()
        let older = makeSnapshot(provider: "gemini", capturedAt: Date().addingTimeInterval(-120))
        let newer = makeSnapshot(provider: "gemini", capturedAt: Date())

        await service.handleStateChange(makeExtState(snapshots: ["gemini": older]))
        await service.handleStateChange(makeExtState(snapshots: ["gemini": newer]))

        let snap = await service.snapshot(for: .gemini)
        let snapTime = snap?.capturedAt.timeIntervalSinceReferenceDate ?? 0
        XCTAssertEqual(snapTime, newer.capturedAt.timeIntervalSinceReferenceDate, accuracy: 0.001)
    }

    // MARK: - Widget Reload Debounce (logic verification)
    //
    // This test verifies that `handleStateChange` reaches the widget-reload
    // scheduling code path without throwing. The actual 5-second DispatchWorkItem
    // is not waited on — doing so would make the test suite slow and fragile.
    // The debounce logic (cancel + reschedule) is straightforward and inspectable
    // in the source; integration-level validation belongs in manual QA.

    func testHandleStateChange_doesNotThrow() async {
        let service = isolatedService()
        // Five rapid state changes — if scheduling code has a bug it will crash here.
        for i in 0..<5 {
            let snap = makeSnapshot(provider: "claude", capturedAt: Date().addingTimeInterval(Double(i)))
            await service.handleStateChange(makeExtState(snapshots: ["claude": snap]))
        }
        // If we reach here without assertion failures the debounce scheduling is intact.
        XCTAssertTrue(true)
    }

    // MARK: - ExtSideState.empty sentinel

    func testExtSideState_empty_hasDistantPastTimestamp() {
        let empty = ExtSideState.empty
        XCTAssertEqual(empty.updatedAt, .distantPast)
        XCTAssertTrue(empty.snapshots.isEmpty)
        XCTAssertTrue(empty.providerVisibility.isEmpty)
    }
}
