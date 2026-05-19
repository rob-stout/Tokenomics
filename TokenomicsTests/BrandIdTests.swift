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

    func testGoogle_currentlyCoversGeminiCLIOnly() {
        // When Phase 4 ships a consumer Gemini reader, this becomes a 2-pool
        // brand and the test updates accordingly.
        XCTAssertEqual(BrandId.google.pools, [.gemini])
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
