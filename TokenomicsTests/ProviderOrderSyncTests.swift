import XCTest
@testable import Tokenomics

final class ProviderOrderSyncTests: XCTestCase {

    private func apply(_ incoming: [String], to current: [String]) -> [String] {
        ProviderOrderSync.applyIncomingOrder(incoming, to: current)
    }

    // MARK: applyIncomingOrder

    func testSharedIdsFollowIncomingAndReceiverOnlyIdsKeepTheirSlots() {
        let current = ["claude", "codex", "chatgpt", "cursor", "suno", "udio"]
        XCTAssertEqual(apply(["udio", "chatgpt", "claude"], to: current),
                       ["udio", "codex", "chatgpt", "cursor", "suno", "claude"])
    }

    func testEmptyIncomingChangesNothing() {
        let current = ["claude", "codex", "chatgpt"]
        XCTAssertEqual(apply([], to: current), current)
    }

    func testAllUnknownIncomingChangesNothing() {
        let current = ["claude", "codex"]
        XCTAssertEqual(apply(["nope", "alsoNope"], to: current), current)
    }

    func testUnknownIdsAreIgnoredAmongKnownOnes() {
        XCTAssertEqual(apply(["x", "chatgpt", "y", "claude"], to: ["claude", "codex", "chatgpt"]),
                       ["chatgpt", "codex", "claude"])
    }

    func testDuplicatesInIncomingCountOnce() {
        let result = apply(["chatgpt", "claude", "chatgpt"], to: ["claude", "codex", "chatgpt"])
        XCTAssertEqual(result, ["chatgpt", "codex", "claude"])
        XCTAssertEqual(Set(result), ["claude", "codex", "chatgpt"])
    }

    func testIdenticalOrderIsStable() {
        let current = ["claude", "codex", "chatgpt"]
        XCTAssertEqual(apply(current, to: current), current)
    }

    func testResultIsAlwaysAPermutationOfCurrent() {
        let current = ["a", "b", "c", "d"]
        XCTAssertEqual(apply(["d", "z", "b", "d"], to: current).sorted(), current)
    }

    // MARK: effectiveOrder

    func testEmptyStoredOrderIsEnumOrder() {
        XCTAssertEqual(ProviderOrderSync.effectiveOrder(stored: []), ProviderId.allCases.map { $0 })
    }

    func testStoredOrderIsKeptAndMissingProvidersAppended() {
        let result = ProviderOrderSync.effectiveOrder(stored: [.udio, .claude])
        XCTAssertEqual(Array(result.prefix(2)), [.udio, .claude])
        XCTAssertEqual(Set(result), Set(ProviderId.allCases))
        XCTAssertEqual(result.count, ProviderId.allCases.count)
    }

    // MARK: Wire / merge

    func testOrderMergeNewestWinsAndTieKeepsCurrent() {
        let old = ProviderOrderSetting(order: ["a"], lastChangedAt: Date(timeIntervalSince1970: 100))
        let new = ProviderOrderSetting(order: ["b"], lastChangedAt: Date(timeIntervalSince1970: 200))
        let tie = ProviderOrderSetting(order: ["c"], lastChangedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(BridgeMerger.newerOrder(old, new), new)
        XCTAssertEqual(BridgeMerger.newerOrder(new, old), new)
        XCTAssertEqual(BridgeMerger.newerOrder(new, tie), new)
        XCTAssertEqual(BridgeMerger.newerOrder(nil, old), old)
        XCTAssertEqual(BridgeMerger.newerOrder(old, nil), old)
    }

    func testSettingsWithoutOrderStillDecodesAndOrderRoundTrips() throws {
        let legacy = Data(#"{"providerVisibility":{}}"#.utf8)
        XCTAssertNil(try JSONDecoder.bridge.decode(BridgeSettings.self, from: legacy).providerOrder)

        let json = Data(#"{"providerVisibility":{},"providerOrder":{"order":["claude","udio"],"lastChangedAt":"2026-11-23T10:00:00Z"}}"#.utf8)
        let decoded = try JSONDecoder.bridge.decode(BridgeSettings.self, from: json)
        XCTAssertEqual(decoded.providerOrder?.order, ["claude", "udio"])
    }

    func testComposerReturnsNewerOrderAndEmitsSettingsWhenOnlyOrderPresent() {
        let mac = ProviderOrderSetting(order: ["claude"], lastChangedAt: Date(timeIntervalSince1970: 0))
        let ext = ProviderOrderSetting(order: ["udio", "claude"], lastChangedAt: Date(timeIntervalSince1970: 500))
        let macSide = MacSideState(updatedAt: Date(), macAppVersion: "x", nativeSnapshots: [:],
                                   providerVisibility: [:], pendingCommands: [], providerOrder: mac)
        let request = BridgeRequest(schemaVersion: 1, envelopeSentAt: Date(), extensionId: "e", snapshots: [],
                                    settings: BridgeSettings(providerVisibility: [:], providerOrder: ext),
                                    requestedActions: nil)
        let response = BridgeResponseComposer.compose(macSide: macSide, request: request, macAppVersion: "x")
        XCTAssertEqual(response.settings?.providerOrder, ext)
    }
}
