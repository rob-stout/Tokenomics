import XCTest
@testable import Tokenomics

/// Regression tests for Cmd+drag brand-tab reordering in the brand-aggregation
/// popover (`BrandTabView` → `UsageViewModel.moveBrand`).
///
/// Brand order is *derived* from `providerOrder`, so reordering a brand means
/// relocating its whole pool block within the provider order. These exercise the
/// pure helper `reorderedProviderOrder(movingBrand:toVisibleIndex:visibleBrands:order:)`
/// so the contract holds without a live view model.
@MainActor
final class BrandReorderTests: XCTestCase {

    // OpenAI is multi-pool (chatgpt + codex); anthropic + copilot are single-pool.
    private let order: [ProviderId] = [.claude, .chatgpt, .codex, .copilot]
    private let visibleBrands: [BrandId] = [.anthropic, .openai, .copilot]

    func testMoveBrandToFront_relocatesWholePoolBlock() {
        let result = UsageViewModel.reorderedProviderOrder(
            movingBrand: .openai,
            toVisibleIndex: 0,
            visibleBrands: visibleBrands,
            order: order
        )
        // OpenAI's two pools move together, ahead of everything else.
        XCTAssertEqual(result, [.chatgpt, .codex, .claude, .copilot])
    }

    func testMoveSinglePoolBrandIntoMiddle() {
        let result = UsageViewModel.reorderedProviderOrder(
            movingBrand: .copilot,
            toVisibleIndex: 1,
            visibleBrands: visibleBrands,
            order: order
        )
        XCTAssertEqual(result, [.claude, .copilot, .chatgpt, .codex])
    }

    func testMultiPoolBlockStaysContiguousAfterMove() {
        let result = UsageViewModel.reorderedProviderOrder(
            movingBrand: .openai,
            toVisibleIndex: 2,
            visibleBrands: visibleBrands,
            order: order
        )
        // Wherever OpenAI lands, chatgpt and codex stay adjacent and in order.
        let r = try! XCTUnwrap(result)
        let chatIdx = try! XCTUnwrap(r.firstIndex(of: .chatgpt))
        let codexIdx = try! XCTUnwrap(r.firstIndex(of: .codex))
        XCTAssertEqual(codexIdx, chatIdx + 1)
    }

    func testSameIndexIsNoOp() {
        XCTAssertNil(UsageViewModel.reorderedProviderOrder(
            movingBrand: .anthropic,
            toVisibleIndex: 0,           // already first
            visibleBrands: visibleBrands,
            order: order
        ))
    }

    func testOutOfRangeIndexIsNoOp() {
        XCTAssertNil(UsageViewModel.reorderedProviderOrder(
            movingBrand: .openai,
            toVisibleIndex: 99,
            visibleBrands: visibleBrands,
            order: order
        ))
    }

    func testUnknownBrandIsNoOp() {
        XCTAssertNil(UsageViewModel.reorderedProviderOrder(
            movingBrand: .google,        // not in visibleBrands
            toVisibleIndex: 0,
            visibleBrands: visibleBrands,
            order: order
        ))
    }

    func testHiddenProvidersPreservedAtTail() {
        // Cursor is in the provider order but not a visible brand tab. Reordering
        // visible brands must not drop it — it lands after the visible blocks.
        let orderWithHidden: [ProviderId] = [.claude, .chatgpt, .codex, .cursor]
        let result = UsageViewModel.reorderedProviderOrder(
            movingBrand: .openai,
            toVisibleIndex: 0,
            visibleBrands: [.anthropic, .openai],   // cursor hidden
            order: orderWithHidden
        )
        XCTAssertEqual(result, [.chatgpt, .codex, .claude, .cursor])
    }

    func testResultIsAPermutation_noProvidersLostOrDuplicated() {
        let result = try! XCTUnwrap(UsageViewModel.reorderedProviderOrder(
            movingBrand: .copilot,
            toVisibleIndex: 0,
            visibleBrands: visibleBrands,
            order: order
        ))
        XCTAssertEqual(Set(result), Set(order))
        XCTAssertEqual(result.count, order.count)
    }
}
