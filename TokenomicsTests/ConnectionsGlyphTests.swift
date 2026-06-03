import XCTest
@testable import Tokenomics

/// Regression tests for the Connections-page icon fixes:
///   - ChatGPT uses the OpenAI mark (not a generic sparkle).
///   - Multi-pool sub-rows use a surface glyph (extension vs CLI) instead of a
///     competing brand mark.
///   - Multi-pool brands expose their pools in a stable display order.
final class ConnectionsGlyphTests: XCTestCase {

    // MARK: - ChatGPT icon = OpenAI mark

    func testChatGPTUsesOpenAIMarkAsset() {
        // The "Codex" asset set IS the OpenAI mark — correct for both OpenAI pools.
        XCTAssertEqual(ProviderId.chatgpt.iconBaseName, "Codex")
        XCTAssertEqual(ProviderId.codex.iconBaseName, "Codex")
    }

    // MARK: - Surface glyphs

    func testBrowserExtensionPoolsUsePuzzleGlyph() {
        XCTAssertEqual(ProviderId.chatgpt.surfaceSymbol, "puzzlepiece.extension")
        XCTAssertEqual(ProviderId.geminiConsumer.surfaceSymbol, "puzzlepiece.extension")
    }

    func testCLIPoolsUseTerminalGlyph() {
        XCTAssertEqual(ProviderId.codex.surfaceSymbol, "terminal")
        XCTAssertEqual(ProviderId.gemini.surfaceSymbol, "terminal")
        XCTAssertEqual(ProviderId.claude.surfaceSymbol, "terminal")
    }

    func testAPIKeyPoolsHaveNoSurfaceGlyph() {
        // API-key providers keep their brand mark — no surface badge.
        XCTAssertNil(ProviderId.stableDiffusion.surfaceSymbol)
        XCTAssertNil(ProviderId.elevenlabs.surfaceSymbol)
        XCTAssertNil(ProviderId.runway.surfaceSymbol)
    }

    // MARK: - Multi-pool ordering (drives sub-row rendering)

    func testOpenAIIsMultiPoolWithWebThenCLIOrder() {
        XCTAssertTrue(BrandId.openai.isMultiPool)
        XCTAssertEqual(BrandId.openai.orderedPools, [.chatgpt, .codex])
    }

    func testGoogleIsMultiPoolWithWebThenCLIOrder() {
        XCTAssertTrue(BrandId.google.isMultiPool)
        XCTAssertEqual(BrandId.google.orderedPools, [.geminiConsumer, .gemini])
    }

    func testSinglePoolBrandIsNotMultiPool() {
        XCTAssertFalse(BrandId.anthropic.isMultiPool)
    }
}
