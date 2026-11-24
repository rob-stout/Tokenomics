import XCTest
@testable import Tokenomics

/// Source-selection rule for ElevenLabs: Mac API key always wins; otherwise a fresh
/// extension reading; otherwise not connected. Never both.
final class ElevenLabsSourceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func bridgeSnapshot(age: TimeInterval, utilization: Double = 0.4) -> BridgeSnapshot {
        let captured = now.addingTimeInterval(-age)
        return BridgeSnapshot(
            provider: "elevenlabs",
            capturedAt: captured,
            estimated: false,
            shortWindow: BridgeWindow(
                label: "Characters",
                utilization: utilization,
                resetsAt: now.addingTimeInterval(86_400),
                windowDurationSec: 30 * 86_400,
                sublabelOverride: nil
            ),
            longWindow: nil,
            planLabel: "Creator"
        )
    }

    private func nativeSubscription() -> ElevenLabsSubscription {
        ElevenLabsSubscription(
            tier: "pro", characterCount: 900, characterLimit: 1000, nextCharacterCountResetUnix: nil
        )
    }

    private func makeProvider(key: String?, bridge: BridgeSnapshot?) -> ElevenLabsProvider {
        ElevenLabsProvider(
            apiKeyReader: { key },
            bridgeSnapshotReader: { bridge },
            subscriptionFetcher: { [self] _ in nativeSubscription() },
            now: { [now] in now }
        )
    }

    // MARK: - Resolver

    func testResolver_keyConfigured_nativeWinsEvenWithFreshBridge() {
        let source = ElevenLabsSourceResolver.resolve(
            nativeKeyConfigured: true, bridge: bridgeSnapshot(age: 10), now: now)
        XCTAssertEqual(source, .native)
    }

    func testResolver_noKey_freshBridge_usesBridge() {
        let source = ElevenLabsSourceResolver.resolve(
            nativeKeyConfigured: false, bridge: bridgeSnapshot(age: 10 * 60), now: now)
        XCTAssertEqual(source, .bridge)
    }

    func testResolver_noKey_pastLiveWindow_stillShowsLastKnownReading() {
        // Browser closed for an hour: the last reading is kept (marked stale in the UI).
        let source = ElevenLabsSourceResolver.resolve(
            nativeKeyConfigured: false, bridge: bridgeSnapshot(age: 60 * 60), now: now)
        XCTAssertEqual(source, .bridge)
    }

    func testResolver_noKey_pastRetention_notConnected() {
        let source = ElevenLabsSourceResolver.resolve(
            nativeKeyConfigured: false, bridge: bridgeSnapshot(age: 49 * 3600), now: now)
        XCTAssertEqual(source, .none)
    }

    func testResolver_noKey_noBridge_notConnected() {
        XCTAssertEqual(
            ElevenLabsSourceResolver.resolve(nativeKeyConfigured: false, bridge: nil, now: now), .none)
    }

    // MARK: - Provider

    func testProvider_keyPresent_usesNativeNumbers_notBridge() async throws {
        let provider = makeProvider(key: "sk_test", bridge: bridgeSnapshot(age: 10, utilization: 0.1))
        let snap = try await provider.fetchUsage()
        XCTAssertEqual(snap.shortWindow.utilization, 90, accuracy: 0.001) // native 900/1000, not bridge 10%
        let source = await provider.lastSource
        XCTAssertEqual(source, .native)
    }

    func testProvider_noKey_freshBridge_connectedAndMapsPercent() async throws {
        let provider = makeProvider(key: nil, bridge: bridgeSnapshot(age: 60, utilization: 0.4))
        let connection = await provider.checkConnection()
        XCTAssertEqual(connection, .connected(plan: "Creator"))
        let snap = try await provider.fetchUsage()
        XCTAssertEqual(snap.shortWindow.utilization, 40, accuracy: 0.001)
        let source = await provider.lastSource
        XCTAssertEqual(source, .bridge)
    }

    func testProvider_noKey_expiredBridge_notConnectedAndFetchThrows() async {
        let provider = makeProvider(key: nil, bridge: bridgeSnapshot(age: 49 * 3600))
        let connection = await provider.checkConnection()
        XCTAssertEqual(connection, .notInstalled)
        do {
            _ = try await provider.fetchUsage()
            XCTFail("expected notAuthenticated")
        } catch {
            guard case AppError.notAuthenticated = error else { return XCTFail("wrong error \(error)") }
        }
    }

    // MARK: - No echo (bridge-sourced reading is never exported as native)

    func testLastSource_bridge_isWhatTheViewModelUsesToSkipExport() async throws {
        // The VM skips setNativeSnapshot when lastSource == .bridge. Verify the signal flips
        // back to native once a key appears, so a real key resumes exporting.
        final class KeyBox: @unchecked Sendable { var key: String? }
        let box = KeyBox()
        let bridge = bridgeSnapshot(age: 10)
        let provider = ElevenLabsProvider(
            apiKeyReader: { box.key },
            bridgeSnapshotReader: { bridge },
            subscriptionFetcher: { [self] _ in nativeSubscription() },
            now: { [now] in now }
        )
        _ = try await provider.fetchUsage()
        var source = await provider.lastSource
        XCTAssertEqual(source, .bridge)
        box.key = "sk_test"
        _ = try await provider.fetchUsage()
        source = await provider.lastSource
        XCTAssertEqual(source, .native)
    }

    // MARK: - Onboarding "Connected" window

    func testFreshlyConnected_slowPollersStayConnectedBetweenPolls() {
        // ElevenLabs/Midjourney/Leonardo/Udio poll every 10 min — the old flat 5-min
        // window flapped for them.
        let snaps = ["elevenlabs": bridgeSnapshot(age: 10 * 60), "grok": bridgeSnapshot(age: 10 * 60)]
        let state = ExtSideState(updatedAt: now, snapshots: snaps, providerVisibility: [:])
        let ids = state.freshlyConnectedProviderIds(at: now)
        XCTAssertTrue(ids.contains(.elevenlabs))
        XCTAssertTrue(ids.contains(.grok))
    }

    func testFreshlyConnected_expiredReadingIsNotConnected() {
        let snaps = ["grok": bridgeSnapshot(age: 49 * 3600)]
        let state = ExtSideState(updatedAt: now, snapshots: snaps, providerVisibility: [:])
        XCTAssertFalse(state.freshlyConnectedProviderIds(at: now).contains(.grok))
    }
}
