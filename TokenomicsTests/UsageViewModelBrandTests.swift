import XCTest
@testable import Tokenomics

/// Exercises the brand-aware helpers added to UsageViewModel (Phase 5.6
/// foundation). Tests target the pure static helpers `brandList(from:)` and
/// `providers(in:from:)` so the contract is verified without standing up a
/// full view model (whose `providerStates` is private-set).
@MainActor
final class UsageViewModelBrandTests: XCTestCase {

    // MARK: - brandList(from:)

    func testBrandList_emptyInputProducesEmptyOutput() {
        XCTAssertEqual(UsageViewModel.brandList(from: []), [])
    }

    func testBrandList_singleProviderProducesOneBrand() {
        let brands = UsageViewModel.brandList(from: [.claude])
        XCTAssertEqual(brands, [.anthropic])
    }

    func testBrandList_collapsesMultiPoolBrandToSingleEntry() {
        // ChatGPT consumer chat + Codex CLI both live under the OpenAI brand.
        // Both visible → brand list should contain `.openai` exactly once.
        let brands = UsageViewModel.brandList(from: [.chatgpt, .codex])
        XCTAssertEqual(brands, [.openai])
    }

    func testBrandList_preservesFirstAppearanceOrder() {
        // Brand ordering follows first-visible-provider order so tabs stay
        // stable as pools come and go within a brand.
        let brands = UsageViewModel.brandList(from: [.claude, .codex, .copilot])
        XCTAssertEqual(brands, [.anthropic, .openai, .copilot])
    }

    func testBrandList_secondPoolOfBrandDoesNotMoveBrandPosition() {
        // .chatgpt and .codex both belong to .openai. If .chatgpt appears
        // first, the brand position should be where .chatgpt is — even when
        // .codex shows up later in the list.
        let brands = UsageViewModel.brandList(from: [.chatgpt, .copilot, .codex])
        XCTAssertEqual(brands, [.openai, .copilot])
    }

    // MARK: - providers(in:from:)

    func testProvidersIn_singlePoolBrand_returnsOneProvider() {
        let result = UsageViewModel.providers(in: .anthropic, from: [.claude, .copilot])
        XCTAssertEqual(result, [.claude])
    }

    func testProvidersIn_multiPoolBrand_returnsBothPools() {
        let result = UsageViewModel.providers(in: .openai, from: [.chatgpt, .codex, .copilot])
        XCTAssertEqual(result, [.chatgpt, .codex])
    }

    func testProvidersIn_brandWithNoVisibleProviders_returnsEmpty() {
        let result = UsageViewModel.providers(in: .openai, from: [.claude, .copilot])
        XCTAssertEqual(result, [])
    }

    func testProvidersIn_preservesInputOrder() {
        // Order matters for stacking pool sections inside a tab. If .codex
        // is visible before .chatgpt, that's the order they should render.
        let result = UsageViewModel.providers(in: .openai, from: [.codex, .copilot, .chatgpt])
        XCTAssertEqual(result, [.codex, .chatgpt])
    }
}
