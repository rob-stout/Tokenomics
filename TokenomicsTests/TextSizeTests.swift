import XCTest
import SwiftUI
@testable import Tokenomics

// MARK: - TextSize Tests
//
// Covers the scale logic that drives popover width + icon sizing when users
// pick Compact / Medium / Large. A regression here means the popover could
// truncate text or clip icons.

final class TextSizeTests: XCTestCase {

    // MARK: - iconScale

    func testIconScale_compactIsIdentity() {
        XCTAssertEqual(TextSize.compact.iconScale, 1.0)
    }

    func testIconScale_mediumIsBetweenCompactAndLarge() {
        XCTAssertGreaterThan(TextSize.medium.iconScale, TextSize.compact.iconScale)
        XCTAssertLessThan(TextSize.medium.iconScale, TextSize.large.iconScale)
    }

    func testIconScale_largeIsGreaterThanOne() {
        XCTAssertGreaterThan(TextSize.large.iconScale, 1.0)
    }

    /// A 16pt icon at Large should land in the 20-22pt range — big enough to
    /// feel balanced next to ~17pt body text, not so big it overwhelms the row.
    func testIconScale_largeProducesReasonableIconSize() {
        let scaled = 16 * TextSize.large.iconScale
        XCTAssertGreaterThanOrEqual(scaled, 20)
        XCTAssertLessThanOrEqual(scaled, 22)
    }

    // MARK: - popoverWidth

    /// Compact with <4 providers should be today's 360pt.
    /// Regression check: if someone changes the base, existing users' popover shifts.
    func testPopoverWidth_compactWithFewProviders_is360() {
        XCTAssertEqual(TextSize.compact.popoverWidth(providerCount: 1), 360)
        XCTAssertEqual(TextSize.compact.popoverWidth(providerCount: 3), 360)
    }

    /// 4+ providers triggers icon-only tabs and needs the wider 400pt base.
    func testPopoverWidth_compactWithManyProviders_is400() {
        XCTAssertEqual(TextSize.compact.popoverWidth(providerCount: 4), 400)
        XCTAssertEqual(TextSize.compact.popoverWidth(providerCount: 5), 400)
    }

    /// Medium adds a fixed amount to each base — enough to keep the extra text
    /// from truncating without making the popover feel oversized.
    func testPopoverWidth_mediumIsWiderThanCompact() {
        let fewProviders = TextSize.medium.popoverWidth(providerCount: 2)
        XCTAssertGreaterThan(fewProviders, TextSize.compact.popoverWidth(providerCount: 2))

        let manyProviders = TextSize.medium.popoverWidth(providerCount: 5)
        XCTAssertGreaterThan(manyProviders, TextSize.compact.popoverWidth(providerCount: 5))
    }

    /// Large is wider than Medium. Guardrail against someone accidentally
    /// setting Medium wider than Large.
    func testPopoverWidth_largeIsWiderThanMedium() {
        for count in [1, 3, 4, 5, 7] {
            XCTAssertGreaterThan(
                TextSize.large.popoverWidth(providerCount: count),
                TextSize.medium.popoverWidth(providerCount: count)
            )
        }
    }

    /// Popover never exceeds 500pt — anything wider feels out of place on a
    /// small laptop screen and starts fighting other menu bar items for space.
    func testPopoverWidth_neverExceedsReasonableCap() {
        for size in TextSize.allCases {
            for count in 1...10 {
                XCTAssertLessThanOrEqual(
                    size.popoverWidth(providerCount: count),
                    500,
                    "Popover width at \(size.displayName) with \(count) providers exceeds 500pt"
                )
            }
        }
    }

    // MARK: - displayName + raw values

    /// Raw values are the persistence contract — changing them silently would
    /// wipe every existing user's saved preference on the next upgrade.
    func testRawValues_stablePersistenceContract() {
        XCTAssertEqual(TextSize.compact.rawValue, "compact")
        XCTAssertEqual(TextSize.medium.rawValue, "medium")
        XCTAssertEqual(TextSize.large.rawValue, "large")
    }

    /// All cases have a non-empty display name (Settings row uses this as the trailing detail text).
    func testDisplayName_allCasesNonEmpty() {
        for size in TextSize.allCases {
            XCTAssertFalse(size.displayName.isEmpty, "\(size) has empty displayName")
        }
    }
}

// MARK: - SettingsService.textSize Tests

final class SettingsServiceTextSizeTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "textSize")
    }

    /// Default (no key stored) is Compact — so existing users see no change on upgrade.
    func testDefault_isCompact() {
        UserDefaults.standard.removeObject(forKey: "textSize")
        XCTAssertEqual(SettingsService.textSize, .compact)
    }

    func testRoundTrip_medium() {
        SettingsService.textSize = .medium
        XCTAssertEqual(SettingsService.textSize, .medium)
    }

    func testRoundTrip_large() {
        SettingsService.textSize = .large
        XCTAssertEqual(SettingsService.textSize, .large)
    }

    /// Unknown stored value falls back to Compact rather than crashing — matters
    /// if a future version adds an option and a user downgrades.
    func testCorruptStoredValue_fallsBackToCompact() {
        UserDefaults.standard.set("bogus-value-from-future", forKey: "textSize")
        XCTAssertEqual(SettingsService.textSize, .compact)
    }
}
