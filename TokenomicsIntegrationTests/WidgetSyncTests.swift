import XCTest
@testable import Tokenomics

// MARK: - Widget Sync Integration Tests

/// Tests the menu bar → widget data sharing roundtrip.
///
/// WidgetDataStore uses file-based storage in the App Group container
/// (not UserDefaults) to sidestep CFPrefs issues between sandboxed/non-sandboxed targets.
///
/// These tests write via the production `WidgetDataStore.write()` path and
/// read back via `WidgetDataStore.read()` — the same code the real app uses.
///
/// The tests write to a per-test temp file rather than the real App Group
/// container: writing there would overwrite the user's live widget data, and on
/// macOS 15+ an unentitled (ad-hoc / CI) build gets a container URL it can't
/// actually use, so a `containerURL != nil` skip check doesn't work.

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

    // XCTest makes a fresh instance per test, so each test gets its own file.
    private let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("WidgetSyncTests-\(UUID().uuidString)")
        .appendingPathComponent("widget-data.json")

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        try super.tearDownWithError()
    }

    // MARK: - Roundtrip Test

    /// Write usage data via the menu bar writer, read it back via the widget reader.
    /// Asserts roundtrip equality on all non-Date fields (Date equality is ±1s due to
    /// JSON encoding precision).
    func testMenuBarToWidget_roundtrip_dataPreserved() throws {
        let entry = makeProviderEntry(utilization: 73.5)
        WidgetDataStore.write(providers: [entry], to: fileURL)

        let snapshot = try XCTUnwrap(
            WidgetDataStore.read(from: fileURL),
            "WidgetDataStore.read() returned nil after write — file may not have been created"
        )

        XCTAssertEqual(snapshot.providers.count, 1)
        let provider = try XCTUnwrap(snapshot.providers.first)
        XCTAssertEqual(provider.id, ProviderId.claude.rawValue)
        XCTAssertEqual(provider.displayName, ProviderId.claude.poolLabel) // widget bakes in the pool label
        XCTAssertEqual(provider.shortWindow.utilization, 73.5, accuracy: 0.001)
        XCTAssertEqual(provider.shortWindow.label, "5-Hour") // widgetLabel strips " Window"
        XCTAssertNil(provider.longWindow)
        XCTAssertEqual(provider.planLabel, "Pro")
    }

    /// Write multiple providers — widget reads back all of them in order.
    func testMenuBarToWidget_multipleProviders_allPreserved() throws {
        let entries: [(ProviderId, ProviderUsageSnapshot)] = [
            makeProviderEntry(id: .claude, utilization: 40.0),
            makeProviderEntry(id: .cursor, utilization: 80.0)
        ]
        WidgetDataStore.write(providers: entries, to: fileURL)

        let snapshot = try XCTUnwrap(WidgetDataStore.read(from: fileURL))
        XCTAssertEqual(snapshot.providers.count, 2)
        XCTAssertEqual(snapshot.providers[0].id, "claude")
        XCTAssertEqual(snapshot.providers[1].id, "cursor")
        XCTAssertEqual(snapshot.providers[1].shortWindow.utilization, 80.0, accuracy: 0.001)
    }

    /// Overwrite: second write replaces first — reader sees the latest data only.
    func testMenuBarToWidget_secondWrite_replacesFirst() throws {
        // First write
        WidgetDataStore.write(providers: [makeProviderEntry(utilization: 25.0)], to: fileURL)
        // Second write with different value
        WidgetDataStore.write(providers: [makeProviderEntry(utilization: 90.0)], to: fileURL)

        let snapshot = try XCTUnwrap(WidgetDataStore.read(from: fileURL))
        let provider = try XCTUnwrap(snapshot.providers.first)
        XCTAssertEqual(provider.shortWindow.utilization, 90.0, accuracy: 0.001)
    }

    // MARK: - Label Transformation Test

    /// WidgetDataStore.widgetLabel strips " Window" and " Today" suffixes.
    /// This is private logic — we verify its effect by round-tripping through write/read.
    func testWidgetLabel_windowSuffix_isStripped() throws {
        WidgetDataStore.write(providers: [makeProviderEntry(utilization: 50)], to: fileURL)

        let snapshot = try XCTUnwrap(WidgetDataStore.read(from: fileURL))
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
        WidgetDataStore.write(providers: [makeProviderEntry(utilization: 55.0)], to: fileURL)

        // First read (simulates widget getting data immediately after write)
        let firstRead = try XCTUnwrap(WidgetDataStore.read(from: fileURL))

        // Second read (simulates widget reading after Sparkle relaunched the app)
        let secondRead = try XCTUnwrap(WidgetDataStore.read(from: fileURL))

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
