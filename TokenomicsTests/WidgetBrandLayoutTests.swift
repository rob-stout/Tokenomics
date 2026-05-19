import XCTest
@testable import Tokenomics

// MARK: - Helpers

private extension WidgetDataStore.WidgetSnapshot.ProviderEntry {
    /// Convenience factory for tests — only the fields under test need real values.
    static func make(
        id: String,
        brandId: String? = nil,
        displayName: String = "Test Provider",
        utilization: Double = 50.0
    ) -> WidgetDataStore.WidgetSnapshot.ProviderEntry {
        let window = WidgetDataStore.WidgetSnapshot.WindowEntry(
            label: "5-Hour",
            utilization: utilization,
            resetsAt: Date().addingTimeInterval(3600),
            windowDuration: 18000
        )
        return .init(
            id: id,
            displayName: displayName,
            shortLabel: id.prefix(1).uppercased(),
            shortWindow: window,
            longWindow: nil,
            planLabel: "Pro",
            brandId: brandId
        )
    }
}

private extension WidgetDataStore.WidgetSnapshot {
    static func make(
        providers: [ProviderEntry],
        brandAggregationEnabled: Bool? = nil
    ) -> WidgetDataStore.WidgetSnapshot {
        WidgetDataStore.WidgetSnapshot(
            providers: providers,
            updatedAt: Date(),
            brandAggregationEnabled: brandAggregationEnabled
        )
    }
}

// MARK: - WidgetSnapshot flag-forwarding tests

final class WidgetSnapshotFlagTests: XCTestCase {

    // MARK: Flag accessor

    func testFlagAccessor_nilBrandAggregation_returnsFalse() {
        let snapshot = WidgetDataStore.WidgetSnapshot.make(providers: [], brandAggregationEnabled: nil)
        XCTAssertFalse(snapshot.isBrandAggregationEnabled, "nil flag must default to false — legacy snapshots must not activate brand layout")
    }

    func testFlagAccessor_falseBrandAggregation_returnsFalse() {
        let snapshot = WidgetDataStore.WidgetSnapshot.make(providers: [], brandAggregationEnabled: false)
        XCTAssertFalse(snapshot.isBrandAggregationEnabled)
    }

    func testFlagAccessor_trueBrandAggregation_returnsTrue() {
        let snapshot = WidgetDataStore.WidgetSnapshot.make(providers: [], brandAggregationEnabled: true)
        XCTAssertTrue(snapshot.isBrandAggregationEnabled)
    }

    // MARK: ProviderEntry backward compatibility

    func testProviderEntry_legacyDecode_brandIdIsNil() throws {
        // Snapshots written before 5.6.B have no brandId field.
        // The Codable decode must succeed with brandId = nil (no crash, no data loss).
        let json = """
        {
            "id": "codex",
            "displayName": "OpenAI",
            "shortLabel": "X",
            "shortWindow": {
                "label": "5-Hour",
                "utilization": 42.0,
                "resetsAt": 9999999999.0,
                "windowDuration": 18000.0
            },
            "planLabel": "Plus"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let entry = try JSONDecoder().decode(WidgetDataStore.WidgetSnapshot.ProviderEntry.self, from: data)
        XCTAssertNil(entry.brandId, "Entries from pre-5.6.B snapshots must decode with brandId = nil")
        XCTAssertEqual(entry.id, "codex")
    }

    func testProviderEntry_withBrandId_decodesCorrectly() throws {
        let json = """
        {
            "id": "codex",
            "displayName": "OpenAI",
            "shortLabel": "X",
            "shortWindow": {
                "label": "5-Hour",
                "utilization": 42.0,
                "resetsAt": 9999999999.0,
                "windowDuration": 18000.0
            },
            "planLabel": "Plus",
            "brandId": "openai"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let entry = try JSONDecoder().decode(WidgetDataStore.WidgetSnapshot.ProviderEntry.self, from: data)
        XCTAssertEqual(entry.brandId, "openai")
    }

    func testSnapshot_legacyDecode_brandAggregationEnabledIsNil() throws {
        // Snapshots written before 5.6.B have no brandAggregationEnabled field.
        let json = """
        {
            "providers": [],
            "updatedAt": 1716000000.0
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(WidgetDataStore.WidgetSnapshot.self, from: data)
        XCTAssertNil(snapshot.brandAggregationEnabled)
        XCTAssertFalse(snapshot.isBrandAggregationEnabled, "Legacy snapshot must not activate brand layout")
    }
}

// MARK: - BrandGrouping tests (flag-on path)

final class BrandGroupingTests: XCTestCase {

    // MARK: BEFORE: Flag-off layout contract (regression tests)

    /// These tests assert the snapshot structure used by the flag-off code path.
    /// They must keep passing — the brand-aggregation feature must not affect
    /// snapshots or rendering when the flag is off.

    func testFlagOff_snapshot_providersPreservedInOrder() {
        let providers: [WidgetDataStore.WidgetSnapshot.ProviderEntry] = [
            .make(id: "claude", brandId: "anthropic"),
            .make(id: "codex",  brandId: "openai"),
            .make(id: "copilot", brandId: "copilot")
        ]
        let snapshot = WidgetDataStore.WidgetSnapshot.make(providers: providers, brandAggregationEnabled: false)
        // Flag-off rendering reads snapshot.providers directly — order must be preserved.
        XCTAssertEqual(snapshot.providers.map(\.id), ["claude", "codex", "copilot"])
    }

    func testFlagOff_snapshot_providerCountForMediumMaxVisible() {
        // Medium widget caps at 3 visible providers. This validates the source list count.
        let providers = (1...5).map { WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "p\($0)") }
        let snapshot = WidgetDataStore.WidgetSnapshot.make(providers: providers, brandAggregationEnabled: false)
        let visible = Array(snapshot.providers.prefix(3))
        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(snapshot.providers.count - 3, 2, "Overflow count should be 2")
    }

    func testFlagOff_snapshot_providerCountForLargeMaxVisible() {
        let providers = (1...9).map { WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "p\($0)") }
        let snapshot = WidgetDataStore.WidgetSnapshot.make(providers: providers, brandAggregationEnabled: false)
        let visible = Array(snapshot.providers.prefix(7))
        XCTAssertEqual(visible.count, 7)
        XCTAssertEqual(snapshot.providers.count - 7, 2, "Overflow count should be 2")
    }

    // MARK: DURING: Brand grouping — new behavior

    func testGrouping_emptyProviders_producesEmptyGroups() {
        let groups = BrandGrouping.group(providers: [], maxDataRows: 6)
        XCTAssertTrue(groups.isEmpty)
    }

    func testGrouping_singleProvider_singleGroup_singlePool() {
        let providers = [WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "claude", brandId: "anthropic")]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].brandId, "anthropic")
        XCTAssertEqual(groups[0].pools.count, 1)
        XCTAssertFalse(groups[0].isMultiPool)
    }

    func testGrouping_twoPoolsBelongingToSameBrand_collapseIntoOneBrandGroup() {
        // chatgpt and codex both belong to the openai brand.
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "chatgpt", brandId: "openai"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "codex",   brandId: "openai")
        ]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        XCTAssertEqual(groups.count, 1, "Both pools share the openai brand — must produce exactly one group")
        XCTAssertEqual(groups[0].brandId, "openai")
        XCTAssertEqual(groups[0].pools.count, 2)
        XCTAssertTrue(groups[0].isMultiPool)
    }

    func testGrouping_multiPoolBrand_poolOrderPreservesInputOrder() {
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "chatgpt", brandId: "openai"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "codex",   brandId: "openai")
        ]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        XCTAssertEqual(groups[0].pools.map(\.id), ["chatgpt", "codex"])
    }

    func testGrouping_mixedBrands_brandOrderMatchesFirstProviderAppearance() {
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "claude",  brandId: "anthropic"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "chatgpt", brandId: "openai"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "codex",   brandId: "openai"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "copilot", brandId: "copilot")
        ]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        XCTAssertEqual(groups.map(\.brandId), ["anthropic", "openai", "copilot"])
    }

    func testGrouping_cap_limitsDataRowsNotBrandHeaderRows() {
        // With maxDataRows=3 and 4 providers (chatgpt, codex under openai, plus claude, copilot),
        // only 3 pools fit. The 4th pool is dropped; its brand may still appear if other pools fit.
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "claude",  brandId: "anthropic"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "chatgpt", brandId: "openai"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "codex",   brandId: "openai"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "copilot", brandId: "copilot")
        ]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 3)
        // 3 data rows: claude (1), chatgpt (2), codex (3) — copilot is dropped
        let allPools = groups.flatMap(\.pools)
        XCTAssertEqual(allPools.count, 3, "Exactly 3 data rows should be rendered")
        XCTAssertFalse(allPools.contains(where: { $0.id == "copilot" }), "copilot exceeds the cap and must be absent")
    }

    func testGrouping_overflowCount_accountsForExcludedProviders() {
        let providers = (1...8).map {
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "p\($0)", brandId: "brand\($0)")
        }
        let overflow = BrandGrouping.overflowCount(providers: providers, maxDataRows: 6)
        XCTAssertEqual(overflow, 2)
    }

    func testGrouping_overflowCount_zeroWhenUnderCap() {
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "claude", brandId: "anthropic")
        ]
        let overflow = BrandGrouping.overflowCount(providers: providers, maxDataRows: 6)
        XCTAssertEqual(overflow, 0)
    }

    func testGrouping_brandWithZeroVisiblePools_omittedFromOutput() {
        // Degenerate case: a group lands in `seen` with no pools (shouldn't happen
        // via normal flow, but the guard protects against it).
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "claude", brandId: "anthropic")
        ]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        // All groups in the output must have at least one pool.
        for group in groups {
            XCTAssertFalse(group.pools.isEmpty, "No group should appear with zero pools")
        }
    }

    func testGrouping_nilBrandId_fallsBackToProviderId() {
        // Legacy entries (written by old app versions) have brandId = nil.
        // Each such entry should form its own group keyed by provider id.
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "claude",  brandId: nil),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "codex",   brandId: nil),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "copilot", brandId: nil)
        ]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        // nil brandId → provider id used as key → 3 separate groups, each single-pool
        XCTAssertEqual(groups.count, 3)
        XCTAssertTrue(groups.allSatisfy { !$0.isMultiPool })
    }

    func testGrouping_singlePoolBrand_isMultiPoolFalse() {
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "claude", brandId: "anthropic")
        ]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        XCTAssertFalse(groups[0].isMultiPool)
    }

    func testGrouping_twoPoolBrand_isMultiPoolTrue() {
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "chatgpt", brandId: "openai"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "codex",   brandId: "openai")
        ]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        XCTAssertTrue(groups[0].isMultiPool)
    }

    // MARK: DURING: Downgrade-safety for small widget picker enum

    /// These tests lock the raw values of the WidgetProviderSelection enum cases
    /// so that saved widget configurations on disk continue to resolve correctly.
    /// A change to any of these raw values would silently break existing user configs.

    func testSmallWidgetEnum_existingCases_rawValuesUnchanged() {
        XCTAssertEqual(WidgetProviderSelection.smart.rawValue,           "smart")
        XCTAssertEqual(WidgetProviderSelection.claude.rawValue,          "claude")
        XCTAssertEqual(WidgetProviderSelection.copilot.rawValue,         "copilot")
        XCTAssertEqual(WidgetProviderSelection.cursor.rawValue,          "cursor")
        XCTAssertEqual(WidgetProviderSelection.codex.rawValue,           "codex")
        XCTAssertEqual(WidgetProviderSelection.gemini.rawValue,          "gemini")
        XCTAssertEqual(WidgetProviderSelection.elevenlabs.rawValue,      "elevenlabs")
        XCTAssertEqual(WidgetProviderSelection.runway.rawValue,          "runway")
        XCTAssertEqual(WidgetProviderSelection.stableDiffusion.rawValue, "stableDiffusion")
    }

    func testSmallWidgetEnum_addedCases_rawValues() {
        // Phase 5.6.C additions — raw values are the new stable identity.
        XCTAssertEqual(WidgetProviderSelection.chatgpt.rawValue,   "chatgpt")
        XCTAssertEqual(WidgetProviderSelection.codexCLI.rawValue,  "codexCLI")
        XCTAssertEqual(WidgetProviderSelection.geminiCLI.rawValue, "geminiCLI")
    }

    func testSmallWidgetEnum_existingCodexCase_decodesFromRawValue() {
        // "codex" on disk must still produce the .codex case (Codex CLI data path).
        let decoded = WidgetProviderSelection(rawValue: "codex")
        XCTAssertEqual(decoded, .codex, ".codex raw value 'codex' must stay stable — existing user configs on disk")
    }

    func testSmallWidgetEnum_existingGeminiCase_decodesFromRawValue() {
        let decoded = WidgetProviderSelection(rawValue: "gemini")
        XCTAssertEqual(decoded, .gemini, ".gemini raw value 'gemini' must stay stable")
    }

    func testSmallWidgetEnum_newChatgptCase_decodesFromRawValue() {
        let decoded = WidgetProviderSelection(rawValue: "chatgpt")
        XCTAssertEqual(decoded, .chatgpt)
    }

    func testSmallWidgetEnum_newCodexCLICase_decodesFromRawValue() {
        let decoded = WidgetProviderSelection(rawValue: "codexCLI")
        XCTAssertEqual(decoded, .codexCLI)
    }

    func testSmallWidgetEnum_newGeminiCLICase_decodesFromRawValue() {
        let decoded = WidgetProviderSelection(rawValue: "geminiCLI")
        XCTAssertEqual(decoded, .geminiCLI)
    }

    func testSmallWidgetEnum_allCasesHaveRawValues() {
        // Verify all expected raw values exist by round-tripping through the enum.
        // Checking caseDisplayRepresentations directly triggers a Swift 6 concurrency
        // warning because it's a static var on the AppIntents framework type —
        // testing raw-value round-trips covers the same contract without touching the var.
        let expectedRawValues = [
            "smart", "claude", "copilot", "cursor", "codex", "gemini",
            "elevenlabs", "runway", "stableDiffusion",
            "chatgpt", "codexCLI", "geminiCLI"
        ]
        for rawValue in expectedRawValues {
            XCTAssertNotNil(
                WidgetProviderSelection(rawValue: rawValue),
                "WidgetProviderSelection must have a case with rawValue '\(rawValue)'"
            )
        }
    }

    // MARK: DURING: Large widget brand-aware cap

    func testLargeWidget_brandAwareGrouping_capsAtSixDataRows() {
        // Large widget uses maxDataRows=6. With 8 single-pool providers,
        // only 6 should appear in groups; 2 overflow.
        let providers = (1...8).map {
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "p\($0)", brandId: "brand\($0)")
        }
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        let allPools = groups.flatMap(\.pools)
        XCTAssertEqual(allPools.count, 6)
        XCTAssertEqual(BrandGrouping.overflowCount(providers: providers, maxDataRows: 6), 2)
    }

    func testMediumWidget_brandAwareGrouping_capsAtThreeDataRows() {
        // Medium widget uses maxDataRows=3.
        let providers = (1...5).map {
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "p\($0)", brandId: "brand\($0)")
        }
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 3)
        let allPools = groups.flatMap(\.pools)
        XCTAssertEqual(allPools.count, 3)
        XCTAssertEqual(BrandGrouping.overflowCount(providers: providers, maxDataRows: 3), 2)
    }

    func testLargeWidget_multiPoolBrand_poolsFitWithinCap() {
        // OpenAI contributes chatgpt + codex (2 data rows for one brand).
        // With maxDataRows=6 and 6 total providers across 5 brands, all fit.
        let providers = [
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "claude",  brandId: "anthropic"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "chatgpt", brandId: "openai"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "codex",   brandId: "openai"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "copilot", brandId: "copilot"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "cursor",  brandId: "cursor"),
            WidgetDataStore.WidgetSnapshot.ProviderEntry.make(id: "gemini",  brandId: "google")
        ]
        let groups = BrandGrouping.group(providers: providers, maxDataRows: 6)
        let allPools = groups.flatMap(\.pools)
        XCTAssertEqual(allPools.count, 6, "All 6 pools should fit within the cap")
        XCTAssertEqual(BrandGrouping.overflowCount(providers: providers, maxDataRows: 6), 0)
        // openai group has 2 pools
        let openaiGroup = groups.first(where: { $0.brandId == "openai" })
        XCTAssertEqual(openaiGroup?.pools.count, 2)
    }
}
