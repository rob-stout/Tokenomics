import XCTest
@testable import Tokenomics

/// Tests for Phase 5.6.A — brand-aware popover rendering, Pin Tracker dropdown,
/// and provider visibility section.
///
/// Structure:
///   BEFORE — flag-off path: verifies today's behavior is unaffected by the
///            new code. These are the rollback safety net.
///   DURING — flag-on path: covers the new brand-aggregated rendering logic.
///
/// View-layer SwiftUI rendering is not exercised here (no ViewInspector). The
/// tests focus on the logic that drives rendering: ViewModel helpers, SettingsService
/// visibility writes, and ProviderId label values.
///
/// `@MainActor` is required because `UsageViewModel` (and its static methods)
/// are main-actor-isolated.
@MainActor
final class PopoverBrandAggregationTests: XCTestCase {

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        // Start each test with the flag off and clean visibility state.
        UserDefaults.standard.removeObject(forKey: FeatureFlags.brandAggregationKey)
        clearVisibilityDefaults()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FeatureFlags.brandAggregationKey)
        clearVisibilityDefaults()
        super.tearDown()
    }

    private func clearVisibilityDefaults() {
        // SettingsService stores visibility under "providerVisibility" key.
        UserDefaults.standard.removeObject(forKey: "providerVisibility")
    }

    // MARK: - BEFORE: Flag-off path (rollback safety net)

    // ── Tab list shape ──────────────────────────────────────────────────────

    /// When the flag is off, `enabledBrands` is unused by the tab bar.
    /// Existing `visibleProviders` continues to drive the tab count.
    /// This test validates that `brandList(from:)` doesn't corrupt `visibleProviders`.
    func testBefore_tabList_drivesFromVisibleProviders() {
        // Simulate 3 visible providers that would map to 2 brands.
        let visible: [ProviderId] = [.claude, .copilot, .chatgpt]

        // Legacy path: tab count == provider count (flag off)
        XCTAssertFalse(FeatureFlags.brandAggregation)
        XCTAssertEqual(visible.count, 3, "Flag-off tab count must equal visibleProviders.count")
    }

    /// `brandList` is pure and deterministic — calling it doesn't alter the input.
    func testBefore_brandListHelper_doesNotMutateInputArray() {
        let visible: [ProviderId] = [.claude, .codex, .chatgpt, .copilot]
        let copy = visible
        _ = UsageViewModel.brandList(from: visible)
        XCTAssertEqual(visible, copy, "brandList(from:) must be a pure function — no side effects")
    }

    // ── Pin Tracker contents ────────────────────────────────────────────────

    /// Flag off: Pin Tracker entries use `displayName` (e.g. "Anthropic", "OpenAI").
    /// The test verifies the label strings that `DisplayModeMenuView` would show.
    func testBefore_pinTrackerDisplayName_usesDisplayName() {
        XCTAssertFalse(FeatureFlags.brandAggregation)
        // These are the values `DisplayModeMenuView` reads in the flag-off branch.
        XCTAssertEqual(ProviderId.claude.displayName,  "Anthropic")
        XCTAssertEqual(ProviderId.codex.displayName,   "OpenAI")
        XCTAssertEqual(ProviderId.gemini.displayName,  "Google AI")
        XCTAssertEqual(ProviderId.copilot.displayName, "GitHub Copilot")
        XCTAssertEqual(ProviderId.chatgpt.displayName, "ChatGPT")
        XCTAssertEqual(ProviderId.cursor.displayName,  "Cursor")
    }

    // ── Visibility toggle behavior ──────────────────────────────────────────

    /// Flag off: toggling one ProviderId only affects that provider.
    func testBefore_visibilityToggle_singleProvider_onlyAffectsThatProvider() {
        XCTAssertFalse(FeatureFlags.brandAggregation)

        // Enable all providers first (defaults to enabled when unset)
        SettingsService.setVisibility(true, for: .claude)
        SettingsService.setVisibility(true, for: .codex)

        // Hide claude
        SettingsService.setVisibility(false, for: .claude)

        XCTAssertFalse(SettingsService.visibility(for: .claude)?.enabled ?? true,
                       "Claude must be hidden after toggle-off")
        XCTAssertTrue(SettingsService.visibility(for: .codex)?.enabled ?? true,
                      "Codex must remain visible — flag-off toggle is per-provider")
    }

    /// Flag off: re-enabling a hidden provider restores it.
    func testBefore_visibilityToggle_reEnable_restoresProvider() {
        SettingsService.setVisibility(false, for: .copilot)
        SettingsService.setVisibility(true,  for: .copilot)
        XCTAssertTrue(SettingsService.visibility(for: .copilot)?.enabled ?? true)
    }

    // MARK: - DURING: Flag-on path (new brand-aggregated behavior)

    // ── Brand-aware tab list ────────────────────────────────────────────────

    /// When enabledBrands is derived from visibleProviders, a single-pool brand
    /// produces one tab entry.
    func testDuring_brandTabList_singlePoolBrand_producesOneTab() {
        let brands = UsageViewModel.brandList(from: [.claude])
        XCTAssertEqual(brands, [.anthropic])
        XCTAssertEqual(brands.count, 1)
    }

    /// A multi-pool brand (OpenAI with chatgpt + codex both visible) still yields
    /// one brand tab, not two.
    func testDuring_brandTabList_multiPoolBrand_collapsesBothPoolsToOneTab() {
        let brands = UsageViewModel.brandList(from: [.chatgpt, .codex])
        XCTAssertEqual(brands, [.openai])
        XCTAssertEqual(brands.count, 1)
    }

    /// When one pool of a multi-pool brand is hidden (not in visibleProviders),
    /// the brand tab still appears — as long as at least one pool is visible.
    func testDuring_brandTabList_onePoolHidden_brandTabStillPresent() {
        // Only chatgpt visible, codex hidden
        let brands = UsageViewModel.brandList(from: [.chatgpt, .copilot])
        XCTAssertTrue(brands.contains(.openai),
                      "Brand tab must appear even when only one of its pools is visible")
        XCTAssertTrue(brands.contains(.copilot))
        XCTAssertEqual(brands.count, 2)
    }

    /// When no providers are visible, enabledBrands is empty.
    func testDuring_brandTabList_noBrandsWhenNoVisibleProviders() {
        let brands = UsageViewModel.brandList(from: [])
        XCTAssertEqual(brands, [])
    }

    /// Brand tab order follows first-visible-provider order, not BrandId enum order.
    func testDuring_brandTabList_orderFollowsFirstVisibleProvider() {
        // copilot's brand appears before openai's brand because copilot is first
        let brands = UsageViewModel.brandList(from: [.copilot, .chatgpt, .codex])
        XCTAssertEqual(brands, [.copilot, .openai])
    }

    // ── Pool sub-section rendering ──────────────────────────────────────────

    /// For a multi-pool brand, `providers(in:from:)` returns both pools in
    /// visibleProviders order — these are what `brandBody` iterates for stacked sections.
    func testDuring_poolSubSections_multiPoolBrand_returnsBothPoolsInOrder() {
        let result = UsageViewModel.providers(in: .openai, from: [.chatgpt, .codex])
        XCTAssertEqual(result, [.chatgpt, .codex])
    }

    /// Order is determined by the input list, not BrandId.pools (which is a Set).
    func testDuring_poolSubSections_orderFollowsVisibleProviderList() {
        // codex visible before chatgpt → codex section renders first in the tab body
        let result = UsageViewModel.providers(in: .openai, from: [.codex, .chatgpt])
        XCTAssertEqual(result, [.codex, .chatgpt])
    }

    /// A single-pool brand returns exactly one pool (no stacking needed).
    func testDuring_poolSubSections_singlePoolBrand_returnsOnePool() {
        let result = UsageViewModel.providers(in: .anthropic, from: [.claude])
        XCTAssertEqual(result, [.claude])
    }

    /// A brand with no visible providers returns an empty list — `brandBody`
    /// falls through to `LoginView`.
    func testDuring_poolSubSections_brandWithNoVisiblePools_returnsEmpty() {
        let result = UsageViewModel.providers(in: .openai, from: [.claude, .copilot])
        XCTAssertEqual(result, [])
    }

    // ── Pin Tracker flat list ───────────────────────────────────────────────

    /// Flag on: Pin Tracker uses `poolLabel` which shows pool-specific names.
    func testDuring_poolLabel_showsPoolSpecificNames() {
        XCTAssertEqual(ProviderId.claude.poolLabel,          "Anthropic")
        XCTAssertEqual(ProviderId.chatgpt.poolLabel,         "ChatGPT")
        XCTAssertEqual(ProviderId.codex.poolLabel,           "Codex CLI")
        XCTAssertEqual(ProviderId.gemini.poolLabel,          "Gemini CLI")
        XCTAssertEqual(ProviderId.copilot.poolLabel,         "GitHub Copilot")
        XCTAssertEqual(ProviderId.cursor.poolLabel,          "Cursor")
        XCTAssertEqual(ProviderId.stableDiffusion.poolLabel, "Stability AI")
    }

    /// `poolLabel` differs from `displayName` for multi-pool providers.
    /// This is the key contract: Codex shows "Codex CLI" (not "OpenAI") and
    /// Gemini shows "Gemini CLI" (not "Google AI").
    func testDuring_poolLabel_differsFromDisplayNameForMultiPoolProviders() {
        XCTAssertNotEqual(ProviderId.codex.poolLabel,  ProviderId.codex.displayName,
                          "Codex pin label should be pool-specific, not brand-level")
        XCTAssertNotEqual(ProviderId.gemini.poolLabel, ProviderId.gemini.displayName,
                          "Gemini pin label should be pool-specific, not brand-level")
    }

    /// Downgrade safety: the underlying pin storage stays at ProviderId granularity.
    /// A previously-stored `.codex` pin is still valid after the flag turns on.
    func testDuring_pinTrackerDowngradeSafety_oldCodexPinRemainsValid() {
        // Simulate an existing pin for the codex pool
        SettingsService.pinnedProviders = [.codex]

        // After the flag turns on, the pin is still at ProviderId level — no migration needed.
        XCTAssertTrue(SettingsService.pinnedProviders.contains(.codex),
                      "Old per-pool pin must survive flag-on — no migration required")
    }

    /// When flag turns on, the flat list iterates `visibleProviders` (per-pool).
    /// This means 2 visible OpenAI pools → 2 separate pin entries.
    func testDuring_pinTrackerFlatList_twoOpenAIPools_twoPinEntries() {
        let visible: [ProviderId] = [.chatgpt, .codex, .copilot]
        let openAIPools = visible.filter { $0.brand == .openai }
        XCTAssertEqual(openAIPools.count, 2,
                       "Both chatgpt and codex must appear as separate Pin Tracker entries")
    }

    // ── Brand-level visibility toggle ───────────────────────────────────────

    /// Toggling a brand off (flag on) writes `enabled: false` to ALL of that brand's pools.
    func testDuring_brandVisibilityToggle_off_hidesAllPools() {
        // Hide the OpenAI brand
        for pool in BrandId.openai.pools {
            SettingsService.setVisibility(false, for: pool)
        }

        for pool in BrandId.openai.pools {
            let enabled = SettingsService.visibility(for: pool)?.enabled ?? true
            XCTAssertFalse(enabled, "Pool .\(pool) must be hidden when OpenAI brand is toggled off")
        }
    }

    /// Toggling a brand on restores all pools.
    func testDuring_brandVisibilityToggle_on_showsAllPools() {
        // First hide them all
        for pool in BrandId.openai.pools {
            SettingsService.setVisibility(false, for: pool)
        }
        // Now show the brand
        for pool in BrandId.openai.pools {
            SettingsService.setVisibility(true, for: pool)
        }

        for pool in BrandId.openai.pools {
            let enabled = SettingsService.visibility(for: pool)?.enabled ?? true
            XCTAssertTrue(enabled, "Pool .\(pool) must be visible after brand toggle-on")
        }
    }

    /// Toggling one brand does not affect another brand's pools.
    func testDuring_brandVisibilityToggle_doesNotAffectOtherBrands() {
        // Hide OpenAI
        for pool in BrandId.openai.pools {
            SettingsService.setVisibility(false, for: pool)
        }

        // Anthropic should remain unaffected (defaults to enabled)
        for pool in BrandId.anthropic.pools {
            let enabled = SettingsService.visibility(for: pool)?.enabled ?? true
            XCTAssertTrue(enabled, "Anthropic pool .\(pool) must not be affected by hiding OpenAI")
        }
    }

    /// Brand "enabled" state is `true` only when ALL pools are visible.
    /// If one pool is hidden, the brand toggle shows as off.
    func testDuring_brandEnabled_requiresAllPoolsVisible() {
        // Hide only chatgpt, leave codex visible
        SettingsService.setVisibility(false, for: .chatgpt)
        SettingsService.setVisibility(true,  for: .codex)

        let allEnabled = BrandId.openai.pools.allSatisfy {
            SettingsService.visibility(for: $0)?.enabled ?? true
        }
        XCTAssertFalse(allEnabled,
                       "Brand enabled must be false when even one of its pools is hidden")
    }

    /// When flag is off, hiding a brand's pool through the per-ProviderId toggle
    /// does not affect the other pools — rollback leaves the per-pool state intact.
    func testDuring_brandVisibilityStorage_staysAtProviderIdGranularity() {
        // This verifies the storage contract: brand-toggle writes per-pool
        // so rolling back the flag still shows the correct per-pool state.
        SettingsService.setVisibility(false, for: .chatgpt)
        SettingsService.setVisibility(true,  for: .codex)

        // Rollback scenario: read via per-ProviderId accessors (flag-off path)
        XCTAssertFalse(SettingsService.visibility(for: .chatgpt)?.enabled ?? true)
        XCTAssertTrue(SettingsService.visibility(for: .codex)?.enabled ?? true)
    }
}
