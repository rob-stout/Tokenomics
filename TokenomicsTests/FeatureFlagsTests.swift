import XCTest
@testable import Tokenomics

final class FeatureFlagsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Each test starts with a clean UserDefaults entry so the default-false
        // contract is honored regardless of run order or prior dev state.
        UserDefaults.standard.removeObject(forKey: FeatureFlags.brandAggregationKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FeatureFlags.brandAggregationKey)
        super.tearDown()
    }

    func testBrandAggregation_defaultsToFalseOnFreshState() {
        XCTAssertFalse(FeatureFlags.brandAggregation, "Brand-aggregation flag must default to false so the new rendering paths stay opt-in")
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
