import XCTest
@testable import Tokenomics

// MARK: - PlanBuilderTests

/// Table-driven tests for PlanBuilder across the full (selection × detection) input matrix.
///
/// Test naming convention: test<what>_<condition>_<expected outcome>
final class PlanBuilderTests: XCTestCase {

    // MARK: - Test Helpers

    /// Convenience: a detection map with the given brands marked as detected.
    private func detected(_ brands: BrandId...) -> [BrandId: BrandDetection] {
        var map: [BrandId: BrandDetection] = [:]
        for brand in brands {
            map[brand] = BrandDetection(
                brand: brand,
                signals: [.cliCredentials(path: "/stub", displayName: "stub")]
            )
        }
        return map
    }

    /// Convenience: an empty detection map (nothing found on disk).
    private var noDetection: [BrandId: BrandDetection] { [:] }

    // MARK: - Empty Selection

    func testBuild_emptySelection_producesEmptyPlan() {
        let plan = PlanBuilder.build(selection: [], detection: noDetection)
        XCTAssertEqual(plan.stepCount, 0)
        XCTAssertEqual(plan.providerCount, 0)
        XCTAssertTrue(plan.steps.isEmpty)
    }

    func testBuild_emptySelection_durationIsNoSetupNeeded() {
        let plan = PlanBuilder.build(selection: [], detection: noDetection)
        XCTAssertEqual(plan.estimatedDuration, "no setup needed")
    }

    // MARK: - Single CLI Brand — Detected

    func testBuild_claudeOnlyDetected_singleConfirmStep() {
        let plan = PlanBuilder.build(
            selection: [.anthropic],
            detection: detected(.anthropic)
        )
        XCTAssertEqual(plan.stepCount, 1)
        XCTAssertTrue(plan.steps[0].title.contains("Confirm"))
        XCTAssertTrue(plan.steps[0].title.contains("Claude Code"))
    }

    func testBuild_claudeDetected_stepTimeEstimateIs5Sec() {
        let plan = PlanBuilder.build(
            selection: [.anthropic],
            detection: detected(.anthropic)
        )
        XCTAssertEqual(plan.steps[0].timeEstimate, "~5 sec")
    }

    func testBuild_cursorDetected_confirmStep() {
        let plan = PlanBuilder.build(
            selection: [.cursor],
            detection: detected(.cursor)
        )
        XCTAssertEqual(plan.stepCount, 1)
        XCTAssertTrue(plan.steps[0].title.contains("Confirm Cursor"))
    }

    // MARK: - Single CLI Brand — Not Detected

    func testBuild_claudeNotDetected_setupStep() {
        let plan = PlanBuilder.build(
            selection: [.anthropic],
            detection: noDetection
        )
        XCTAssertEqual(plan.stepCount, 1)
        XCTAssertTrue(plan.steps[0].title.contains("Set up Claude Code"))
    }

    func testBuild_claudeNotDetected_stepTimeEstimateIs2Min() {
        let plan = PlanBuilder.build(
            selection: [.anthropic],
            detection: noDetection
        )
        XCTAssertEqual(plan.steps[0].timeEstimate, "~2 min")
    }

    func testBuild_copilotNotDetected_titleMentionsCopilot() {
        let plan = PlanBuilder.build(
            selection: [.copilot],
            detection: noDetection
        )
        XCTAssertTrue(plan.steps[0].title.contains("GitHub Copilot"))
    }

    func testBuild_cursorNotDetected_setupStep() {
        let plan = PlanBuilder.build(
            selection: [.cursor],
            detection: noDetection
        )
        XCTAssertTrue(plan.steps[0].title.contains("Set up Cursor"))
    }

    // MARK: - Extension Batch — OpenAI with chatgpt pool

    func testBuild_openaiSelected_extensionStepFirst() {
        let plan = PlanBuilder.build(
            selection: [.openai],
            detection: noDetection
        )
        // OpenAI has both chatgpt (extension-only) and codex (CLI) in its pools.
        // The extension step must come before any CLI step.
        let firstTitle = plan.steps.first?.title ?? ""
        XCTAssertTrue(firstTitle.contains("browser extension"),
            "First step for OpenAI should be the extension install, got: \(firstTitle)")
    }

    func testBuild_openaiSelected_coversListContainsChatGPT() {
        let plan = PlanBuilder.build(
            selection: [.openai],
            detection: noDetection
        )
        guard let extensionStep = plan.steps.first else {
            XCTFail("Expected at least one step")
            return
        }
        let covers = extensionStep.covers ?? []
        XCTAssertTrue(covers.contains(where: { $0.contains("ChatGPT") }),
            "Extension step covers list should mention ChatGPT, got: \(covers)")
    }

    func testBuild_openaiSelected_hasBothExtensionAndCliStep() {
        // OpenAI = chatgpt (extension) + codex (CLI) — should produce 2 steps
        let plan = PlanBuilder.build(
            selection: [.openai],
            detection: noDetection
        )
        XCTAssertEqual(plan.stepCount, 2,
            "OpenAI selection should produce extension step + codex CLI step")
    }

    // MARK: - Extension Batch — Multiple Extension Brands

    func testBuild_openaiAndMidjourney_extensionStepBatchesBoth() {
        let plan = PlanBuilder.build(
            selection: [.openai, .midjourney],
            detection: noDetection
        )
        // Both openai (chatgpt pool) and midjourney are web-companion-only.
        // They must be batched into ONE extension step, not two.
        let extensionSteps = plan.steps.filter { $0.title.contains("browser extension") }
        XCTAssertEqual(extensionSteps.count, 1,
            "Multiple extension-batch brands must produce exactly one extension step")
    }

    func testBuild_openaiAndMidjourney_extensionCoversListContainsBoth() {
        let plan = PlanBuilder.build(
            selection: [.openai, .midjourney],
            detection: noDetection
        )
        guard let extensionStep = plan.steps.first(where: { $0.title.contains("browser extension") }) else {
            XCTFail("Expected an extension step")
            return
        }
        let covers = extensionStep.covers ?? []
        XCTAssertTrue(covers.contains(where: { $0.contains("ChatGPT") }))
        XCTAssertTrue(covers.contains(where: { $0.contains("Midjourney") }))
    }

    // MARK: - No Extension Brands — Step Omitted

    func testBuild_onlyClaudeSelected_noExtensionStep() {
        let plan = PlanBuilder.build(
            selection: [.anthropic],
            detection: noDetection
        )
        let extensionSteps = plan.steps.filter { $0.title.contains("browser extension") }
        XCTAssertEqual(extensionSteps.count, 0, "Claude-only selection must not produce an extension step")
    }

    func testBuild_onlyCopilotSelected_noExtensionStep() {
        let plan = PlanBuilder.build(
            selection: [.copilot],
            detection: noDetection
        )
        let extensionSteps = plan.steps.filter { $0.title.contains("browser extension") }
        XCTAssertEqual(extensionSteps.count, 0)
    }

    // MARK: - API Key Lane

    func testBuild_stabilitySelected_apiKeyStep() {
        let plan = PlanBuilder.build(
            selection: [.stability],
            detection: noDetection
        )
        XCTAssertEqual(plan.stepCount, 1)
        XCTAssertTrue(plan.steps[0].title.contains("API key"))
        XCTAssertTrue(plan.steps[0].title.contains("Stability AI"))
    }

    func testBuild_stabilitySelected_descriptionMentionsSite() {
        let plan = PlanBuilder.build(
            selection: [.stability],
            detection: noDetection
        )
        XCTAssertTrue(plan.steps[0].description.contains("stability.ai"))
    }

    func testBuild_runwaySelected_apiKeyStep() {
        let plan = PlanBuilder.build(
            selection: [.runway],
            detection: noDetection
        )
        XCTAssertTrue(plan.steps[0].title.contains("Runway"))
        XCTAssertEqual(plan.steps[0].timeEstimate, "~30 sec")
    }

    func testBuild_elevenlabsSelected_apiKeyStep() {
        let plan = PlanBuilder.build(
            selection: [.elevenlabs],
            detection: noDetection
        )
        XCTAssertTrue(plan.steps[0].title.contains("ElevenLabs"))
    }

    // MARK: - Step Numbering

    func testBuild_multipleSteps_numberingStartsAt1AndIsContiguous() {
        // Claude (CLI) + Stability (API key) = 2 steps numbered 1, 2
        let plan = PlanBuilder.build(
            selection: [.anthropic, .stability],
            detection: noDetection
        )
        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.steps[0].number, 1)
        XCTAssertEqual(plan.steps[1].number, 2)
    }

    func testBuild_extensionPlusCLIPlusAPIKey_threeSteps() {
        let plan = PlanBuilder.build(
            selection: [.openai, .anthropic, .stability],
            detection: noDetection
        )
        // openai → extension step + codex CLI step; anthropic → CLI step; stability → API key step
        // = extension + codex + claude + stability = 4 steps
        XCTAssertEqual(plan.stepCount, 4,
            "OpenAI (ext + CLI) + Anthropic (CLI) + Stability (API key) = 4 steps, got \(plan.stepCount)")
    }

    // MARK: - Step Ordering: extension → CLI → API key

    func testBuild_mixedLanes_extensionStepIsFirst() {
        let plan = PlanBuilder.build(
            selection: [.stability, .openai, .anthropic],
            detection: noDetection
        )
        XCTAssertTrue(plan.steps[0].title.contains("browser extension"),
            "Extension batch step must be first, got: \(plan.steps[0].title)")
    }

    func testBuild_mixedLanes_apiKeyStepsAreLast() {
        let plan = PlanBuilder.build(
            selection: [.openai, .anthropic, .stability],
            detection: noDetection
        )
        let lastStep = plan.steps.last
        XCTAssertTrue(lastStep?.title.contains("API key") == true,
            "API key step must be last, got: \(lastStep?.title ?? "nil")")
    }

    // MARK: - Detected vs Not-Detected copy difference

    func testBuild_geminiDetected_confirmCopy() {
        let plan = PlanBuilder.build(
            selection: [.google],
            detection: detected(.google)
        )
        XCTAssertTrue(plan.steps[0].title.contains("Confirm Gemini CLI"))
        XCTAssertTrue(plan.steps[0].description.contains("Already installed"))
    }

    func testBuild_geminiNotDetected_setupCopy() {
        let plan = PlanBuilder.build(
            selection: [.google],
            detection: noDetection
        )
        XCTAssertTrue(plan.steps[0].title.contains("Set up Gemini CLI"))
    }

    func testBuild_copilotDetected_confirmCopy() {
        let plan = PlanBuilder.build(
            selection: [.copilot],
            detection: detected(.copilot)
        )
        XCTAssertTrue(plan.steps[0].title.contains("Confirm"))
        XCTAssertTrue(plan.steps[0].description.contains("gh CLI"))
    }

    // MARK: - providerCount

    func testBuild_anthropicAndOpenai_providerCountIsCorrect() {
        // anthropic pools = [.claude] (1), openai pools = [.chatgpt, .codex] (2)
        let plan = PlanBuilder.build(
            selection: [.anthropic, .openai],
            detection: noDetection
        )
        XCTAssertEqual(plan.providerCount, 3)
    }

    func testBuild_singleSinglePoolBrand_providerCountIsOne() {
        let plan = PlanBuilder.build(
            selection: [.cursor],
            detection: noDetection
        )
        XCTAssertEqual(plan.providerCount, 1)
    }

    // MARK: - estimatedDuration

    func testBuild_oneDetectedCLIBrand_durationIsAboutAMinute() {
        // Detected CLI = 5 sec → "under a minute"
        let plan = PlanBuilder.build(
            selection: [.anthropic],
            detection: detected(.anthropic)
        )
        // 5 sec total → "under a minute"
        XCTAssertEqual(plan.estimatedDuration, "under a minute")
    }

    func testBuild_oneUndetectedCLIBrand_durationIsAboutAMinute() {
        // Undetected CLI = 120 sec → "~2 minutes"
        let plan = PlanBuilder.build(
            selection: [.anthropic],
            detection: noDetection
        )
        XCTAssertEqual(plan.estimatedDuration, "~2 minutes")
    }

    func testBuild_extensionStepOnly_durationIsAboutAMinute() {
        // Extension = 60 sec → "about a minute"
        let plan = PlanBuilder.build(
            selection: [.midjourney],
            detection: noDetection
        )
        XCTAssertEqual(plan.estimatedDuration, "about a minute")
    }

    // MARK: - Step IDs are unique

    func testBuild_allBrands_stepNumbersAreUnique() {
        let plan = PlanBuilder.build(
            selection: Set(BrandId.allCases),
            detection: noDetection
        )
        let ids = plan.steps.map(\.number)
        XCTAssertEqual(ids.count, Set(ids).count, "Step numbers must be unique")
    }

    // MARK: - Step.id conformance (Identifiable)

    func testBuild_steps_idMatchesNumber() {
        let plan = PlanBuilder.build(
            selection: [.anthropic, .cursor],
            detection: noDetection
        )
        for step in plan.steps {
            XCTAssertEqual(step.id, step.number)
        }
    }

    // MARK: - Covers list only on extension step

    func testBuild_cliStep_coversIsNil() {
        let plan = PlanBuilder.build(
            selection: [.anthropic],
            detection: noDetection
        )
        XCTAssertNil(plan.steps[0].covers)
    }

    func testBuild_apiKeyStep_coversIsNil() {
        let plan = PlanBuilder.build(
            selection: [.stability],
            detection: noDetection
        )
        XCTAssertNil(plan.steps[0].covers)
    }

    func testBuild_extensionStep_coversIsNonNil() {
        let plan = PlanBuilder.build(
            selection: [.midjourney],
            detection: noDetection
        )
        guard let extensionStep = plan.steps.first else {
            XCTFail("Expected extension step")
            return
        }
        XCTAssertNotNil(extensionStep.covers)
    }
}
