import XCTest
@testable import Tokenomics

final class ProviderVisibilitySyncTests: XCTestCase {

    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    private func setting(_ enabled: Bool, _ at: Date) -> ProviderVisibilitySetting {
        ProviderVisibilitySetting(enabled: enabled, lastChangedAt: at)
    }

    // MARK: incomingChanges

    func testNewerRemoteSettingIsAdopted() {
        let changes = ProviderVisibilitySync.incomingChanges(
            remote: ["suno": setting(false, newer)],
            local: ["suno": setting(true, older)]
        )
        XCTAssertEqual(changes.map(\.id), [.suno])
        XCTAssertEqual(changes.first?.setting, setting(false, newer))
    }

    func testOlderOrEqualRemoteSettingIsIgnored() {
        let changes = ProviderVisibilitySync.incomingChanges(
            remote: ["suno": setting(false, older), "udio": setting(false, newer)],
            local: ["suno": setting(true, newer), "udio": setting(true, newer)]
        )
        XCTAssertTrue(changes.isEmpty, "only a strictly newer change wins, so an echo is a no-op")
    }

    func testRemoteSettingWinsWhenMacHasNoStamp() {
        let changes = ProviderVisibilitySync.incomingChanges(
            remote: ["grok": setting(false, older)],
            local: [:]
        )
        XCTAssertEqual(changes.map(\.id), [.grok])
    }

    func testProvidersOnlyTheExtensionKnowsAreSkipped() {
        let changes = ProviderVisibilitySync.incomingChanges(
            remote: ["someFutureSite": setting(false, newer), "claude": setting(false, newer)],
            local: [:]
        )
        XCTAssertEqual(changes.map(\.id), [.claude])
    }

    // MARK: seededStamps

    func testHiddenProvidersWithoutStampGetOne() {
        let seeded = ProviderVisibilitySync.seededStamps(hidden: [.cursor], existing: [:], now: newer)
        XCTAssertEqual(seeded["cursor"], setting(false, newer))
    }

    func testExistingStampsAndShownProvidersAreLeftAlone() {
        let existing = ["cursor": setting(true, older)]
        let seeded = ProviderVisibilitySync.seededStamps(hidden: [.cursor], existing: existing, now: newer)
        XCTAssertEqual(seeded, existing, "a provider that already has a stamp keeps it")
        XCTAssertNil(ProviderVisibilitySync.seededStamps(hidden: [], existing: [:], now: newer)["claude"])
    }

    func testSeededHideBeatsAnOlderExtensionSetting() {
        // Hidden on the Mac before sync existed; the extension turned it on long ago.
        let local = ProviderVisibilitySync.seededStamps(hidden: [.copilot], existing: [:], now: newer)
        let changes = ProviderVisibilitySync.incomingChanges(remote: ["copilot": setting(true, older)], local: local)
        XCTAssertTrue(changes.isEmpty)
    }
}
