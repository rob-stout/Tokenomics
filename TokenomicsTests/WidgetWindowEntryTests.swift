import XCTest
@testable import Tokenomics

// MARK: - WidgetSnapshot.WindowEntry sublabelOverride Tests
//
// Companion to WindowUsageTests: the popover's WindowUsage.sublabelOverride fix
// doesn't automatically reach desktop widgets — WindowEntry is a separate Codable
// struct with its own shortTimeUntilReset formatter. These tests cover the
// additive-field decode contract (mirroring brandId/iconBaseName/surfaceSymbol
// on ProviderEntry) and the formatter itself.

final class WidgetWindowEntryTests: XCTestCase {

    // MARK: - Legacy Decode (Additive-Field Contract)

    /// Snapshots written before this fix have no sublabelOverride field.
    /// Decode must succeed with nil (no crash, no data loss) — same contract
    /// as ProviderEntry.brandId.
    func testWindowEntry_legacyDecode_sublabelOverrideIsNil() throws {
        let json = """
        {
            "label": "5-Hour",
            "utilization": 0.0,
            "resetsAt": 9999999999.0,
            "windowDuration": 18000.0
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let entry = try JSONDecoder().decode(WidgetDataStore.WidgetSnapshot.WindowEntry.self, from: data)
        XCTAssertNil(entry.sublabelOverride, "Entries from pre-fix snapshots must decode with sublabelOverride = nil")
        XCTAssertEqual(entry.label, "5-Hour")
    }

    func testWindowEntry_withSublabelOverride_decodesCorrectly() throws {
        let json = """
        {
            "label": "5-Hour",
            "utilization": 0.0,
            "resetsAt": 9999999999.0,
            "windowDuration": 18000.0,
            "sublabelOverride": "No session"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let entry = try JSONDecoder().decode(WidgetDataStore.WidgetSnapshot.WindowEntry.self, from: data)
        XCTAssertEqual(entry.sublabelOverride, "No session")
    }

    // MARK: - shortTimeUntilReset (Widget-Side Formatter)

    /// Regression: without the override, distantFuture leaks the same fabricated
    /// weekday bug in the widget's own formatter as it did in the popover's.
    func testShortTimeUntilReset_distantFutureWithoutOverride_isTheBugThisFixPrevents() {
        let window = WidgetDataStore.WidgetSnapshot.WindowEntry(
            label: "5-Hour",
            utilization: 0,
            resetsAt: .distantFuture,
            windowDuration: 5 * 3600
        )
        XCTAssertEqual(window.shortTimeUntilReset, "Sun",
            "distantFuture's abbreviated weekday is Sun — why every nil-resetsAt window must set sublabelOverride")
    }

    /// With the override, shortTimeUntilReset returns it verbatim — no countdown
    /// formatting, no weekday, nothing composed around it.
    func testShortTimeUntilReset_withOverride_returnsVerbatim() {
        let window = WidgetDataStore.WidgetSnapshot.WindowEntry(
            label: "5-Hour",
            utilization: 0,
            resetsAt: .distantFuture,
            windowDuration: 5 * 3600,
            sublabelOverride: "No session"
        )
        XCTAssertEqual(window.shortTimeUntilReset, "No session")
    }

    /// Non-regression: a real countdown (no override) is unaffected by the fix.
    func testShortTimeUntilReset_realResetWithinHours_unaffectedByFix() {
        let window = WidgetDataStore.WidgetSnapshot.WindowEntry(
            label: "5-Hour",
            utilization: 42,
            resetsAt: Date().addingTimeInterval(2 * 3600 + 15 * 60 + 5),
            windowDuration: 5 * 3600
        )
        XCTAssertEqual(window.shortTimeUntilReset, "2h 15m")
    }

    // MARK: - makeEntries Wiring (App-Side Bake)

    private static func sampleSnapshot(shortSublabelOverride: String?) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "5-Hour Window",
                utilization: 0,
                resetsAt: .distantFuture,
                windowDuration: 5 * 3600,
                sublabelOverride: shortSublabelOverride
            ),
            longWindow: nil,
            planLabel: "Max",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    /// The app-side bake must carry the model's sublabelOverride into the widget
    /// snapshot — this is the exact gap that let the widget bug survive the
    /// popover-only fix.
    func testMakeEntries_sublabelOverride_isThreadedThrough() {
        let snapshot = Self.sampleSnapshot(shortSublabelOverride: "No active session")
        let entries = WidgetDataStore.makeEntries(providers: [(.claude, snapshot)])

        XCTAssertEqual(entries.first?.shortWindow.sublabelOverride, "No session",
            "makeEntries must bake the model's override into the widget snapshot (compacted for widget width)")
    }

    /// Windows with a real reset time must not pick up a stray override.
    func testMakeEntries_noOverride_staysNil() {
        let snapshot = ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "5-Hour Window",
                utilization: 50,
                resetsAt: Date().addingTimeInterval(3600),
                windowDuration: 5 * 3600
            ),
            longWindow: nil,
            planLabel: "Max",
            extraUsage: nil,
            creditsBalance: nil
        )
        let entries = WidgetDataStore.makeEntries(providers: [(.claude, snapshot)])
        XCTAssertNil(entries.first?.shortWindow.sublabelOverride)
    }

    /// Other providers' overrides (usage counts, not "no session" text) must pass
    /// through unchanged — the compacting rule only targets the specific string.
    func testMakeEntries_usageCountOverride_passesThroughUnchanged() {
        let snapshot = Self.sampleSnapshot(shortSublabelOverride: "120 / 500 used")
        let entries = WidgetDataStore.makeEntries(providers: [(.cursor, snapshot)])
        XCTAssertEqual(entries.first?.shortWindow.sublabelOverride, "120 / 500 used")
    }
}
