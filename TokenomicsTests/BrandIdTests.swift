import XCTest
@testable import Tokenomics

final class BrandIdTests: XCTestCase {

    // MARK: - Brand → pools map

    func testAnthropic_isUnifiedSinglePool() {
        XCTAssertEqual(BrandId.anthropic.pools, [.claude])
    }

    func testOpenAI_coversConsumerChatAndCodexCLI() {
        XCTAssertEqual(BrandId.openai.pools, [.chatgpt, .codex])
    }

    func testGoogle_coversBothCLIAndConsumerPool() {
        // Phase 4 shipped the geminiConsumer reader — Google is now a 2-pool
        // brand: .gemini (CLI) + .geminiConsumer (web app via browser extension).
        XCTAssertEqual(BrandId.google.pools, [.gemini, .geminiConsumer])
    }

    func testSingleProviderBrands_haveOneElementPoolSet() {
        let singlePoolBrands: [BrandId] = [
            .copilot, .cursor, .stability, .midjourney,
            .runway, .elevenlabs, .suno, .udio
        ]
        for brand in singlePoolBrands {
            XCTAssertEqual(brand.pools.count, 1, "Brand \(brand) should be single-pool today; got \(brand.pools.count) pools")
        }
    }

    // MARK: - ProviderId → brand inverse

    func testProviderToBrand_isWellDefined() {
        for providerId in ProviderId.allCases {
            let brand = providerId.brand
            XCTAssertTrue(
                brand.pools.contains(providerId),
                "ProviderId .\(providerId) maps to brand .\(brand), but that brand's pools \(brand.pools) doesn't include the provider — inverse is broken"
            )
        }
    }

    func testBrandPools_partitionAllProviderIds() {
        // Every ProviderId must appear in exactly one brand's pools.
        var seen: [ProviderId: BrandId] = [:]
        for brand in BrandId.allCases {
            for providerId in brand.pools {
                XCTAssertNil(
                    seen[providerId],
                    "ProviderId .\(providerId) appears in both .\(seen[providerId]!) and .\(brand) — brands must partition ProviderIds"
                )
                seen[providerId] = brand
            }
        }
        let coveredProviders = Set(seen.keys)
        let allProviders = Set(ProviderId.allCases)
        let missing = allProviders.subtracting(coveredProviders)
        XCTAssertTrue(missing.isEmpty, "ProviderIds not covered by any brand: \(missing)")
    }

    // MARK: - Phase 4 geminiConsumer assertions

    func testGeminiConsumer_brandIsGoogle() {
        XCTAssertEqual(ProviderId.geminiConsumer.brand, .google,
            "geminiConsumer must map to the google brand — same account, separate usage meter")
    }

    func testGooglePools_containsBothCLIAndConsumer() {
        XCTAssertTrue(BrandId.google.pools.contains(.gemini),        "google brand must include CLI pool")
        XCTAssertTrue(BrandId.google.pools.contains(.geminiConsumer), "google brand must include consumer pool")
    }

    func testIsWebCompanionOnly_geminiConsumer_isTrue() {
        // geminiConsumer is extension-fed — no CLI tool, no local credentials.
        XCTAssertTrue(PlanBuilder.isWebCompanionOnlyForTesting(.geminiConsumer),
            "geminiConsumer must be classified as web-companion-only so PlanBuilder routes it through the extension batch")
    }

    func testIsWebCompanionOnly_geminiCLI_isFalse() {
        // The CLI pool has its own local credentials path — must NOT be in the extension batch.
        XCTAssertFalse(PlanBuilder.isWebCompanionOnlyForTesting(.gemini),
            "gemini CLI must not be web-companion-only — it has a local credentials path")
    }

    // MARK: - Display strings

    func testCompanyAttribution_setOnlyForMultiPoolFamilies() {
        // The brands with corporate attribution are the ones where the brand
        // name itself doesn't encode the company (Claude → Anthropic, ChatGPT
        // → OpenAI, Gemini → Google). The rest carry company in the brand
        // name itself.
        XCTAssertEqual(BrandId.anthropic.companyAttribution, "Anthropic")
        XCTAssertEqual(BrandId.openai.companyAttribution,    "OpenAI")
        XCTAssertEqual(BrandId.google.companyAttribution,    "Google")
        XCTAssertNil(BrandId.copilot.companyAttribution)
        XCTAssertNil(BrandId.cursor.companyAttribution)
        XCTAssertNil(BrandId.midjourney.companyAttribution)
    }

    func testDisplayName_matchesMultiSelectRowLabels() {
        // The brand displayName drives the user-facing label everywhere
        // (popover tab, multi-select row, Pin Tracker entry). These should
        // stay in sync with MultiSelectStep's row label strings.
        XCTAssertEqual(BrandId.anthropic.displayName,  "Claude")
        XCTAssertEqual(BrandId.openai.displayName,     "ChatGPT")
        XCTAssertEqual(BrandId.google.displayName,     "Gemini")
        XCTAssertEqual(BrandId.copilot.displayName,    "GitHub Copilot")
        XCTAssertEqual(BrandId.cursor.displayName,     "Cursor")
    }
}
