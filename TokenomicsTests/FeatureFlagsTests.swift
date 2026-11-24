import XCTest
@testable import Tokenomics

final class FeatureFlagsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Each test starts with a clean entry; the developer's own setting is put back after.
        saved = UserDefaults.standard.object(forKey: FeatureFlags.brandAggregationKey)
        UserDefaults.standard.removeObject(forKey: FeatureFlags.brandAggregationKey)
    }

    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: FeatureFlags.brandAggregationKey) }
        else { UserDefaults.standard.removeObject(forKey: FeatureFlags.brandAggregationKey) }
        super.tearDown()
    }

    private var saved: Any?

    func testBrandAggregation_defaultsToTrueOnFreshState() {
        XCTAssertTrue(FeatureFlags.brandAggregation, "Group-by-company is on unless the user turns it off")
    }

    func testBrandAggregation_persistsAfterEnable() {
        FeatureFlags.brandAggregation = true
        XCTAssertTrue(FeatureFlags.brandAggregation)

        // Verify the raw UserDefaults read matches — confirms the defaults
        // command path (`defaults write … -bool true`) stays in sync.
        XCTAssertTrue(UserDefaults.standard.bool(forKey: FeatureFlags.brandAggregationKey))
    }

    func testBrandAggregation_canBeFlippedBack() {
        FeatureFlags.brandAggregation = true
        FeatureFlags.brandAggregation = false
        XCTAssertFalse(FeatureFlags.brandAggregation)
    }

    func testBrandAggregationKey_matchesDocumentedDefaultsCommand() {
        // The CLI fallback command documented in FeatureFlags.swift uses this
        // exact key. Changing it breaks the documented escape hatch — assert
        // the contract so accidental renames surface immediately.
        XCTAssertEqual(FeatureFlags.brandAggregationKey, "tokenomics.brandAggregation.enabled")
    }
}
