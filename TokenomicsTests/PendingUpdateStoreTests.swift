import XCTest
@testable import Tokenomics

// MARK: - PendingUpdateStore Tests
//
// Covers the logic that keeps the "update available" blue dot visible across
// app restarts. Uses a disposable UserDefaults suite per test so runs don't
// leak into the real defaults.

final class PendingUpdateStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: PendingUpdateStore!

    override func setUp() {
        super.setUp()
        suiteName = "PendingUpdateStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = PendingUpdateStore(defaults: defaults, key: "PendingUpdateVersion")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - shouldShowBadge

    /// No stored version → no badge. First-ever launch state.
    func testShouldShowBadge_noStoredVersion_returnsFalse() {
        XCTAssertFalse(store.shouldShowBadge(currentVersion: "2.7.4"))
    }

    /// Stored version is newer than what's running → show the dot.
    /// This is the core "user quit without installing, reopen app, dot comes back" case.
    func testShouldShowBadge_storedNewerThanCurrent_returnsTrue() {
        store.mark(version: "2.7.5")
        XCTAssertTrue(store.shouldShowBadge(currentVersion: "2.7.4"))
    }

    /// Stored version equals current → user already updated, clear the stale record.
    func testShouldShowBadge_storedEqualsCurrent_returnsFalseAndClears() {
        store.mark(version: "2.7.5")
        XCTAssertFalse(store.shouldShowBadge(currentVersion: "2.7.5"))
        XCTAssertNil(defaults.string(forKey: "PendingUpdateVersion"))
    }

    /// Stored version older than current → somehow ran a newer build, clear stale record.
    func testShouldShowBadge_storedOlderThanCurrent_returnsFalseAndClears() {
        store.mark(version: "2.7.3")
        XCTAssertFalse(store.shouldShowBadge(currentVersion: "2.7.4"))
        XCTAssertNil(defaults.string(forKey: "PendingUpdateVersion"))
    }

    /// Numeric comparison — ensure "2.7.10" is treated as newer than "2.7.9",
    /// not the lexicographic opposite. Catches the classic version-string bug.
    func testShouldShowBadge_numericComparison_doubleDigitPatch() {
        store.mark(version: "2.7.10")
        XCTAssertTrue(store.shouldShowBadge(currentVersion: "2.7.9"))
    }

    /// Numeric comparison — minor bump across double-digit boundary.
    func testShouldShowBadge_numericComparison_doubleDigitMinor() {
        store.mark(version: "2.10.0")
        XCTAssertTrue(store.shouldShowBadge(currentVersion: "2.9.5"))
    }

    /// Major version jump.
    func testShouldShowBadge_majorVersionBump_returnsTrue() {
        store.mark(version: "3.0.0")
        XCTAssertTrue(store.shouldShowBadge(currentVersion: "2.7.4"))
    }

    // MARK: - mark / clear

    /// mark() persists the version so a fresh store instance can read it back.
    /// Simulates "quit and relaunch" without actually quitting.
    func testMark_persistsAcrossStoreInstances() {
        store.mark(version: "2.7.5")

        let freshStore = PendingUpdateStore(defaults: defaults, key: "PendingUpdateVersion")
        XCTAssertTrue(freshStore.shouldShowBadge(currentVersion: "2.7.4"))
    }

    /// clear() wipes the stored version entirely.
    func testClear_removesStoredVersion() {
        store.mark(version: "2.7.5")
        store.clear()

        XCTAssertNil(defaults.string(forKey: "PendingUpdateVersion"))
        XCTAssertFalse(store.shouldShowBadge(currentVersion: "2.7.4"))
    }

    /// mark() overwrites an earlier pending version — e.g. 2.7.5 detected, then
    /// 2.7.6 comes out before the user acts on 2.7.5.
    func testMark_overwritesPreviousVersion() {
        store.mark(version: "2.7.5")
        store.mark(version: "2.7.6")

        XCTAssertEqual(defaults.string(forKey: "PendingUpdateVersion"), "2.7.6")
        XCTAssertTrue(store.shouldShowBadge(currentVersion: "2.7.5"))
    }
}
