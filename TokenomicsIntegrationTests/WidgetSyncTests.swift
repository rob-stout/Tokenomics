import XCTest
@testable import Tokenomics

// MARK: - Widget Sync Integration Tests

/// Tests the menu bar → widget data sharing roundtrip.
///
/// WidgetDataStore uses file-based storage in the App Group container
/// (not UserDefaults) to sidestep CFPrefs issues between sandboxed/non-sandboxed targets.
///
/// These tests write via the production `WidgetDataStore.write()` path and
/// read back via `WidgetDataStore.read()` — the same paths the real app uses.
///
/// The App Group identifier is `group.com.robstout.tokenomics`. In CI (where
/// the App Group container isn't provisioned), `containerURL` returns nil and
/// `write()` silently no-ops. The test detects this and skips gracefully.

final class WidgetSyncTests: XCTestCase {

    // MARK: - Helpers

    private func makeProviderEntry(
        id: ProviderId = .claude,
        utilization: Double = 60.0
    ) -> (ProviderId, ProviderUsageSnapshot) {
        let snapshot = ProviderUsageSnapshot(
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
        return (id, snapshot)
    }

    private var appGroupAvailable: Bool {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetDataStore.appGroupId) != nil
    }

    // MARK: - Roundtrip Test

    /// Write usage data via the menu bar writer, read it back via the widget reader.
    /// Asserts roundtrip equality on all non-Date fields (Date equality is ±1s due to
    /// JSON encoding precision).
    func testMenuBarToWidget_roundtrip_dataPreserved() throws {
        guard appGroupAvailable else {
            throw XCTSkip("App Group container unavailable in this environment (CI without entitlements)")
        }

        let entry = makeProviderEntry(utilization: 73.5)
        WidgetDataStore.write(providers: [entry])

        let snapshot = try XCTUnwrap(
            WidgetDataStore.read(),
            "WidgetDataStore.read() returned nil after write — file may not have been created"
        )

        XCTAssertEqual(snapshot.providers.count, 1)
        let provider = try XCTUnwrap(snapshot.providers.first)
        XCTAssertEqual(provider.id, ProviderId.claude.rawValue)
        XCTAssertEqual(provider.displayName, ProviderId.claude.displayName)
        XCTAssertEqual(provider.shortWindow.utilization, 73.5, accuracy: 0.001)
        XCTAssertEqual(provider.shortWindow.label, "5-Hour") // widgetLabel strips " Window"
        XCTAssertNil(provider.longWindow)
        XCTAssertEqual(provider.planLabel, "Pro")
    }

    /// Write multiple providers — widget reads back all of them in order.
    func testMenuBarToWidget_multipleProviders_allPreserved() throws {
        guard appGroupAvailable else {
            throw XCTSkip("App Group container unavailable in this environment (CI without entitlements)")
        }

        let entries: [(ProviderId, ProviderUsageSnapshot)] = [
            makeProviderEntry(id: .claude, utilization: 40.0),
            makeProviderEntry(id: .cursor, utilization: 80.0)
        ]
        WidgetDataStore.write(providers: entries)

        let snapshot = try XCTUnwrap(WidgetDataStore.read())
        XCTAssertEqual(snapshot.providers.count, 2)
        XCTAssertEqual(snapshot.providers[0].id, "claude")
        XCTAssertEqual(snapshot.providers[1].id, "cursor")
        XCTAssertEqual(snapshot.providers[1].shortWindow.utilization, 80.0, accuracy: 0.001)
    }

    /// Overwrite: second write replaces first — reader sees the latest data only.
    func testMenuBarToWidget_secondWrite_replacesFirst() throws {
        guard appGroupAvailable else {
            throw XCTSkip("App Group container unavailable in this environment (CI without entitlements)")
        }

        // First write
        WidgetDataStore.write(providers: [makeProviderEntry(utilization: 25.0)])
        // Second write with different value
        WidgetDataStore.write(providers: [makeProviderEntry(utilization: 90.0)])

        let snapshot = try XCTUnwrap(WidgetDataStore.read())
        let provider = try XCTUnwrap(snapshot.providers.first)
        XCTAssertEqual(provider.shortWindow.utilization, 90.0, accuracy: 0.001)
    }

    // MARK: - Label Transformation Test

    /// WidgetDataStore.widgetLabel strips " Window" and " Today" suffixes.
    /// This is private logic — we verify its effect by round-tripping through write/read.
    func testWidgetLabel_windowSuffix_isStripped() throws {
        guard appGroupAvailable else {
            throw XCTSkip("App Group container unavailable in this environment (CI without entitlements)")
        }

        WidgetDataStore.write(providers: [makeProviderEntry(utilization: 50)])

        let snapshot = try XCTUnwrap(WidgetDataStore.read())
        let provider = try XCTUnwrap(snapshot.providers.first)
        // "5-Hour Window" → "5-Hour"
        XCTAssertEqual(provider.shortWindow.label, "5-Hour")
    }

    // MARK: - Sparkle Relaunch Simulation

    /// Simulates the Sparkle post-install relaunch: write data, then read it back
    /// in a fresh call (no in-memory cache). This catches any file-write atomicity
    /// issues that could cause the widget to see stale or empty data after an update.
    ///
    /// WidgetDataStore uses `.atomic` write — so this test verifies the file persists
    /// correctly across what would be a process boundary (simulated by a second read).
    func testSparkleRelaunch_dataPersistedAcrossReads() throws {
        guard appGroupAvailable else {
            throw XCTSkip("App Group container unavailable in this environment (CI without entitlements)")
        }

        WidgetDataStore.write(providers: [makeProviderEntry(utilization: 55.0)])

        // First read (simulates widget getting data immediately after write)
        let firstRead = try XCTUnwrap(WidgetDataStore.read())

        // Second read (simulates widget reading after Sparkle relaunched the app)
        let secondRead = try XCTUnwrap(WidgetDataStore.read())

        // Both reads must see the same data — no cache invalidation issue
        XCTAssertEqual(firstRead.providers.count, secondRead.providers.count)
        if let firstUtil = firstRead.providers.first?.shortWindow.utilization,
           let secondUtil = secondRead.providers.first?.shortWindow.utilization {
            XCTAssertEqual(firstUtil, secondUtil, accuracy: 0.001)
        } else {
            XCTFail("Expected provider utilization in both reads")
        }
    }
}
