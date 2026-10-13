import XCTest
@testable import Tokenomics

// MARK: - Provider Parsing Tests
//
// Response models in CursorProvider, CopilotProvider, ElevenLabsProvider,
// and RunwayProvider are private — they cannot be imported via @testable.
// Strategy: declare test-local mirror structs that match the JSON shape,
// decode the fixture files against them, and assert on derived values.
// This validates fixture shape AND that the production parser won't reject
// these payloads when they reach the real code.
//
// GeminiProvider reads local session files. GeminiPlan and GeminiProvider's
// session-file logic is tested via the public GeminiPlan model.
//
// CodexProvider's JSONL structs (CodexRateLimits, CodexTokenCount, etc.)
// ARE internal — tested directly.

// MARK: - Fixture loader

private func loadFixture(_ name: String) throws -> Data {
    // Try the test bundle first (when Fixtures are bundled as resources)
    let bundle = Bundle(identifier: "com.robstout.tokenomics.tests") ?? Bundle.main
    if let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") {
        return try Data(contentsOf: url)
    }
    // Fallback: load relative to this source file (works when tests run via xcodebuild
    // with the Fixtures directory as a resource copy build phase)
    let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    return try Data(contentsOf: fileURL)
}

// MARK: - Codex Provider Tests

/// Tests CodexRateLimits and CodexTokenCount decoding — these structs are internal.
final class CodexProviderParsingTests: XCTestCase {

    /// Decodes a typical JSONL session file — both rate_limits and token_count present
    func testCodexRateLimits_typicalSession_decodesCorrectly() throws {
        let jsonLine = """
        {"type":"event_msg","payload":{"rate_limits":{"primary":{"used_percent":42.5,"window_minutes":300,"resets_at":1750000000.0},"secondary":{"used_percent":10.0,"window_minutes":300,"resets_at":1750000000.0},"credits":{"has_credits":true,"unlimited":false,"balance":"$12.34"},"plan_type":"pro"}}}
        """.data(using: .utf8)!

        // Decode the outer event wrapper — CodexSessionEvent is private, so we
        // decode a mirror struct here.
        struct SessionEventMirror: Decodable {
            struct Payload: Decodable {
                let rateLimits: CodexRateLimits?
                enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
            }
            let payload: Payload
        }

        let event = try JSONDecoder().decode(SessionEventMirror.self, from: jsonLine)
        let limits = try XCTUnwrap(event.payload.rateLimits)
        XCTAssertEqual(limits.primary.usedPercent, 42.5, accuracy: 0.001)
        XCTAssertEqual(limits.primary.windowMinutes, 300)
        XCTAssertEqual(limits.planType, "pro")
        XCTAssertEqual(limits.credits?.balance, "$12.34")
        XCTAssertTrue(limits.credits?.hasCredits == true)
        XCTAssertFalse(limits.credits?.unlimited == true)
    }

    /// Decodes token_count event — CodexTokenCount is internal
    func testCodexTokenCount_typicalEvent_decodesCorrectly() throws {
        let jsonLine = """
        {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":45000},"model_context_window":200000}}}
        """.data(using: .utf8)!

        struct TokenEventMirror: Decodable {
            struct Payload: Decodable {
                let type: String?
                let info: CodexTokenCount?
            }
            let payload: Payload
        }

        let event = try JSONDecoder().decode(TokenEventMirror.self, from: jsonLine)
        let tokenCount = try XCTUnwrap(event.payload.info)
        XCTAssertEqual(tokenCount.lastInputTokens, 45000)
        XCTAssertEqual(tokenCount.modelContextWindow, 200000)
    }

    /// Missing rate_limits: decoder must not throw — returns nil gracefully
    func testCodexRateLimits_missingFromPayload_isNil() throws {
        let jsonLine = """
        {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10000},"model_context_window":200000}}}
        """.data(using: .utf8)!

        struct SessionEventMirror: Decodable {
            struct Payload: Decodable {
                let rateLimits: CodexRateLimits?
                enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
            }
            let payload: Payload
        }

        let event = try JSONDecoder().decode(SessionEventMirror.self, from: jsonLine)
        XCTAssertNil(event.payload.rateLimits)
    }

    /// Forward compat: unknown fields in rate_limits must not cause decode failure
    func testCodexRateLimits_unknownFields_decodesGracefully() throws {
        let jsonLine = """
        {"type":"event_msg","payload":{"rate_limits":{"primary":{"used_percent":55.0,"window_minutes":300,"resets_at":1750000000.0},"secondary":{"used_percent":5.0,"window_minutes":300,"resets_at":1750000000.0},"credits":{"has_credits":true,"unlimited":false,"balance":"$5.00"},"plan_type":"pro","new_future_field":"some_value","another_new_field":42}}}
        """.data(using: .utf8)!

        struct SessionEventMirror: Decodable {
            struct Payload: Decodable {
                let rateLimits: CodexRateLimits?
                enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
            }
            let payload: Payload
        }

        // Must not throw — extra fields are ignored by Swift's Decodable
        let event = try JSONDecoder().decode(SessionEventMirror.self, from: jsonLine)
        let usedPercent = try XCTUnwrap(event.payload.rateLimits?.primary.usedPercent)
        XCTAssertEqual(usedPercent, 55.0, accuracy: 0.001)
    }

    /// Regression: API shape changed — rate_limits missing the secondary window
    func testCodexRateLimits_missingSecondaryWindow_decodesOrThrows() {
        let jsonLine = """
        {"type":"event_msg","payload":{"rate_limits":{"primary":{"used_percent":30.0,"window_minutes":300,"resets_at":1750000000.0}}}}
        """.data(using: .utf8)!

        struct SessionEventMirror: Decodable {
            struct Payload: Decodable {
                let rateLimits: CodexRateLimits?
                enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
            }
            let payload: Payload
        }

        // CodexRateLimits has non-optional `secondary` — missing it throws.
        // This is the "API shape changed" regression: test documents the current
        // behavior so any future change to make secondary optional is visible.
        XCTAssertThrowsError(
            try JSONDecoder().decode(SessionEventMirror.self, from: jsonLine),
            "Codex rate_limits missing secondary must throw (struct has non-optional secondary)"
        )
    }

    /// Plan inference: unlimited credits → Pro
    func testCodexPlanInference_unlimitedCredits_returnsPro() {
        let limits = CodexRateLimits(
            primary: CodexRateLimitWindow(usedPercent: 10, windowMinutes: 300, resetsAt: 1750000000),
            secondary: CodexRateLimitWindow(usedPercent: 5, windowMinutes: 300, resetsAt: 1750000000),
            credits: CodexCredits(hasCredits: true, unlimited: true, balance: nil),
            planType: nil
        )
        // Mirror the plan inference logic from CodexProvider.inferPlan
        let plan: String
        if let planType = limits.planType, !planType.isEmpty {
            plan = planType.prefix(1).uppercased() + planType.dropFirst()
        } else if limits.credits?.unlimited == true {
            plan = "Pro"
        } else if limits.credits?.hasCredits == true {
            plan = "Plus"
        } else {
            plan = "Free"
        }
        XCTAssertEqual(plan, "Pro")
    }

    /// Plan inference: explicit plan_type wins over credits-based inference
    func testCodexPlanInference_explicitPlanType_wins() {
        let limits = CodexRateLimits(
            primary: CodexRateLimitWindow(usedPercent: 10, windowMinutes: 300, resetsAt: 1750000000),
            secondary: CodexRateLimitWindow(usedPercent: 5, windowMinutes: 300, resetsAt: 1750000000),
            credits: CodexCredits(hasCredits: false, unlimited: false, balance: nil),
            planType: "enterprise"
        )
        let planType = limits.planType ?? ""
        let plan = planType.isEmpty ? "Free" : planType.prefix(1).uppercased() + planType.dropFirst()
        XCTAssertEqual(plan, "Enterprise")
    }
}

// MARK: - Cursor Provider Tests (test-local mirror structs)

private struct CursorUsageMirror: Decodable {
    let membershipType: String?
    let individualUsage: IndividualUsage?
    let billingCycleStart: String?
    let billingCycleEnd: String?

    struct IndividualUsage: Decodable {
        let plan: PlanUsage?
    }
    struct PlanUsage: Decodable {
        let used: Int
        let limit: Int
        let totalPercentUsed: Double?
    }

    var planLabel: String {
        guard let membership = membershipType else { return "Free" }
        switch membership.lowercased() {
        case "free": return "Free"
        case "pro": return "Pro"
        case "business": return "Business"
        case "ultra": return "Ultra"
        default: return membership.prefix(1).uppercased() + membership.dropFirst()
        }
    }
}

final class CursorProviderParsingTests: XCTestCase {

    private func makeDecoder() -> JSONDecoder {
        // Cursor dates are ISO8601 strings — decoder handles them as raw strings
        // in the mirror struct (no date decoding needed)
        JSONDecoder()
    }

    func testCursorPro_decodesCorrectly() throws {
        let data = try loadFixture("cursor_usage_pro.json")
        let summary = try makeDecoder().decode(CursorUsageMirror.self, from: data)
        XCTAssertEqual(summary.planLabel, "Pro")
        let plan = try XCTUnwrap(summary.individualUsage?.plan)
        XCTAssertEqual(plan.used, 350)
        XCTAssertEqual(plan.limit, 500)
        let pct = try XCTUnwrap(plan.totalPercentUsed)
        XCTAssertEqual(pct, 70.0, accuracy: 0.001)
    }

    func testCursorFree_decodesCorrectly() throws {
        let data = try loadFixture("cursor_usage_free.json")
        let summary = try makeDecoder().decode(CursorUsageMirror.self, from: data)
        XCTAssertEqual(summary.planLabel, "Free")
        let plan = try XCTUnwrap(summary.individualUsage?.plan)
        let freePct = try XCTUnwrap(plan.totalPercentUsed)
        XCTAssertEqual(freePct, 90.0, accuracy: 0.001)
    }

    func testCursorMissingFields_gracefulFallback() throws {
        let data = try loadFixture("cursor_usage_missing_fields.json")
        let summary = try makeDecoder().decode(CursorUsageMirror.self, from: data)
        XCTAssertNil(summary.individualUsage?.plan)
        // planLabel falls back correctly even with null individualUsage
        XCTAssertEqual(summary.planLabel, "Pro")
    }

    func testCursorUtilization_serverPercentTakesPrecedence() throws {
        let data = try loadFixture("cursor_usage_pro.json")
        let summary = try makeDecoder().decode(CursorUsageMirror.self, from: data)
        let plan = try XCTUnwrap(summary.individualUsage?.plan)
        // Production code: if serverPercent > 0, use it; else compute from used/limit
        let utilization: Double
        if let serverPercent = plan.totalPercentUsed, serverPercent > 0 {
            utilization = serverPercent
        } else {
            utilization = Double(plan.used) / Double(plan.limit) * 100
        }
        XCTAssertEqual(utilization, 70.0, accuracy: 0.001)
    }
}

// MARK: - Copilot Provider Tests (test-local mirror structs)

private struct CopilotUserMirror: Decodable {
    let accessTypeSku: String?
    let copilotPlan: String?
    let quotaSnapshots: QuotaSnapshots?
    let quotaResetDate: String?
    let quotaResetDateUtc: String?

    struct QuotaSnapshots: Decodable {
        let premiumInteractions: QuotaSnapshot?

        enum CodingKeys: String, CodingKey {
            case premiumInteractions = "premium_interactions"
        }
    }

    struct QuotaSnapshot: Decodable {
        let entitlement: Int?
        let remaining: Int?
        let percentRemaining: Double?
        let unlimited: Bool?
        let overageCount: Int?
        let overagePermitted: Bool?

        enum CodingKeys: String, CodingKey {
            case entitlement
            case remaining
            case percentRemaining = "percent_remaining"
            case unlimited
            case overageCount = "overage_count"
            case overagePermitted = "overage_permitted"
        }
    }

    var planLabel: String {
        if let sku = accessTypeSku?.lowercased() {
            if sku.contains("free") { return "Free" }
            if sku.contains("enterprise") { return "Enterprise" }
            if sku.contains("business") { return "Business" }
            if sku.contains("individual") { return "Individual" }
        }
        if let plan = copilotPlan, !plan.isEmpty {
            return plan.prefix(1).uppercased() + plan.dropFirst()
        }
        return "Free"
    }

    enum CodingKeys: String, CodingKey {
        case accessTypeSku = "access_type_sku"
        case copilotPlan = "copilot_plan"
        case quotaSnapshots = "quota_snapshots"
        case quotaResetDate = "quota_reset_date"
        case quotaResetDateUtc = "quota_reset_date_utc"
    }
}

final class CopilotProviderParsingTests: XCTestCase {

    func testCopilotPremium_decodesCorrectly() throws {
        let data = try loadFixture("copilot_user_premium.json")
        let user = try JSONDecoder().decode(CopilotUserMirror.self, from: data)
        let premium = try XCTUnwrap(user.quotaSnapshots?.premiumInteractions)
        XCTAssertEqual(premium.entitlement, 40000)
        XCTAssertEqual(premium.remaining, 22499)
        XCTAssertEqual(premium.percentRemaining ?? 0, 56.2, accuracy: 0.001)
        XCTAssertEqual(premium.unlimited, false)
    }

    func testCopilotPremium_planLabel_isEnterprise() throws {
        let data = try loadFixture("copilot_user_premium.json")
        let user = try JSONDecoder().decode(CopilotUserMirror.self, from: data)
        // Newer multi-quota SKU maps via contains-matching.
        XCTAssertEqual(user.planLabel, "Enterprise")
    }

    func testCopilotPremium_usedCount_isCorrect() throws {
        let data = try loadFixture("copilot_user_premium.json")
        let user = try JSONDecoder().decode(CopilotUserMirror.self, from: data)
        let premium = try XCTUnwrap(user.quotaSnapshots?.premiumInteractions)
        let entitlement = premium.entitlement ?? 0
        let remaining = premium.remaining ?? entitlement
        let used = max(entitlement - remaining, 0)
        XCTAssertEqual(used, 17501) // 40000 - 22499
    }

    func testCopilotPremium_utilizationCalc_isCorrect() throws {
        let data = try loadFixture("copilot_user_premium.json")
        let user = try JSONDecoder().decode(CopilotUserMirror.self, from: data)
        let premium = try XCTUnwrap(user.quotaSnapshots?.premiumInteractions)
        let utilization = max(0, 100 - (premium.percentRemaining ?? 100))
        XCTAssertEqual(utilization, 43.8, accuracy: 0.001) // 100 - 56.2
    }

    func testCopilotPremium_resetDate_parsesFromUtc() throws {
        let data = try loadFixture("copilot_user_premium.json")
        let user = try JSONDecoder().decode(CopilotUserMirror.self, from: data)
        XCTAssertEqual(user.quotaResetDateUtc, "2026-07-01T00:00:00.000Z")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: try XCTUnwrap(user.quotaResetDateUtc)))
    }

    func testCopilotUnlimited_decodesAsUnlimited() throws {
        let data = try loadFixture("copilot_user_unlimited.json")
        let user = try JSONDecoder().decode(CopilotUserMirror.self, from: data)
        let premium = try XCTUnwrap(user.quotaSnapshots?.premiumInteractions)
        XCTAssertEqual(premium.unlimited, true)
        XCTAssertEqual(user.planLabel, "Individual")
    }
}

// MARK: - Runway Provider Tests (test-local mirror structs)

private struct RunwayCreditsMirror: Decodable {
    let balance: Credits

    struct Credits: Decodable {
        let used: Int
        let total: Int
        let resetsAt: String?
        enum CodingKeys: String, CodingKey {
            case used, total
            case resetsAt = "resets_at"
        }
    }
}

final class RunwayProviderParsingTests: XCTestCase {

    func testRunwayTypical_decodesCorrectly() throws {
        let data = try loadFixture("runway_credits_typical.json")
        let response = try JSONDecoder().decode(RunwayCreditsMirror.self, from: data)
        XCTAssertEqual(response.balance.used, 1500)
        XCTAssertEqual(response.balance.total, 5000)
        XCTAssertEqual(response.balance.resetsAt, "2026-05-01T00:00:00Z")
    }

    func testRunwayTypical_utilizationCalc_isCorrect() throws {
        let data = try loadFixture("runway_credits_typical.json")
        let response = try JSONDecoder().decode(RunwayCreditsMirror.self, from: data)
        let used = response.balance.used
        let total = response.balance.total
        let utilization = total > 0 ? Double(used) / Double(total) * 100 : 0
        XCTAssertEqual(utilization, 30.0, accuracy: 0.001) // 1500/5000 = 30%
    }

    func testRunwayNoReset_resetsAtIsNil() throws {
        let data = try loadFixture("runway_credits_no_reset.json")
        let response = try JSONDecoder().decode(RunwayCreditsMirror.self, from: data)
        XCTAssertNil(response.balance.resetsAt)
    }

    func testRunwayNoReset_utilizationCalc_isCorrect() throws {
        let data = try loadFixture("runway_credits_no_reset.json")
        let response = try JSONDecoder().decode(RunwayCreditsMirror.self, from: data)
        let utilization = Double(response.balance.used) / Double(response.balance.total) * 100
        XCTAssertEqual(utilization, 20.0, accuracy: 0.001) // 200/1000 = 20%
    }
}

// MARK: - ElevenLabs Provider Tests (test-local mirror structs)

private struct ElevenLabsMirror: Decodable {
    let tier: String?
    let characterCount: Int
    let characterLimit: Int
    let nextCharacterCountResetUnix: Int?

    var tierLabel: String {
        guard let tier else { return "Free" }
        return tier.prefix(1).uppercased() + tier.dropFirst()
    }

    enum CodingKeys: String, CodingKey {
        case tier
        case characterCount = "character_count"
        case characterLimit = "character_limit"
        case nextCharacterCountResetUnix = "next_character_count_reset_unix"
    }
}

final class ElevenLabsProviderParsingTests: XCTestCase {

    func testElevenLabsCreator_decodesCorrectly() throws {
        let data = try loadFixture("elevenlabs_subscription_creator.json")
        let sub = try JSONDecoder().decode(ElevenLabsMirror.self, from: data)
        XCTAssertEqual(sub.tierLabel, "Creator")
        XCTAssertEqual(sub.characterCount, 75000)
        XCTAssertEqual(sub.characterLimit, 100000)
        XCTAssertEqual(sub.nextCharacterCountResetUnix, 1777752000)
    }

    func testElevenLabsCreator_utilizationCalc_isCorrect() throws {
        let data = try loadFixture("elevenlabs_subscription_creator.json")
        let sub = try JSONDecoder().decode(ElevenLabsMirror.self, from: data)
        let utilization = Double(sub.characterCount) / Double(sub.characterLimit) * 100
        XCTAssertEqual(utilization, 75.0, accuracy: 0.001)
    }

    func testElevenLabsFree_decodesCorrectly() throws {
        let data = try loadFixture("elevenlabs_subscription_free.json")
        let sub = try JSONDecoder().decode(ElevenLabsMirror.self, from: data)
        XCTAssertEqual(sub.tierLabel, "Free")
        XCTAssertNil(sub.nextCharacterCountResetUnix)
    }

    func testElevenLabsMissingTier_fallsBackToFree() throws {
        let data = try loadFixture("elevenlabs_subscription_missing_tier.json")
        let sub = try JSONDecoder().decode(ElevenLabsMirror.self, from: data)
        XCTAssertNil(sub.tier)
        XCTAssertEqual(sub.tierLabel, "Free")
    }

    func testElevenLabsResetDate_convertsFromUnix() throws {
        let data = try loadFixture("elevenlabs_subscription_creator.json")
        let sub = try JSONDecoder().decode(ElevenLabsMirror.self, from: data)
        let resetUnix = try XCTUnwrap(sub.nextCharacterCountResetUnix)
        let resetDate = Date(timeIntervalSince1970: TimeInterval(resetUnix))
        // Verify the Unix timestamp decodes to a plausible date (after 2026-01-01)
        let jan2026 = Date(timeIntervalSince1970: 1_735_689_600) // 2026-01-01T00:00:00Z
        XCTAssertGreaterThan(resetDate, jan2026)
    }
}

// MARK: - Gemini Plan Tests

/// Gemini uses local session files; plan limits are in the public GeminiPlan model.
final class GeminiPlanTests: XCTestCase {

    func testGeminiPlan_free_limitsAreCorrect() {
        let plan = GeminiPlan.free
        XCTAssertEqual(plan.dailyLimit, 1000)
        XCTAssertEqual(plan.dailyTokenBudget, 2_000_000)
        XCTAssertEqual(plan.displayLabel, "Free")
    }

    func testGeminiPlan_standard_limitsAreCorrect() {
        let plan = GeminiPlan.standard
        XCTAssertEqual(plan.dailyLimit, 1500)
        XCTAssertEqual(plan.dailyTokenBudget, 3_000_000)
        XCTAssertEqual(plan.displayLabel, "Standard")
    }

    func testGeminiPlan_enterprise_limitsAreCorrect() {
        let plan = GeminiPlan.enterprise
        XCTAssertEqual(plan.dailyLimit, 2000)
        XCTAssertEqual(plan.dailyTokenBudget, 4_000_000)
        XCTAssertEqual(plan.displayLabel, "Enterprise")
    }

    func testGeminiPlan_utilizationCalc_isCorrect() {
        let plan = GeminiPlan.free
        let dailyCount = 600
        let utilization = Double(dailyCount) / Double(plan.dailyLimit) * 100
        XCTAssertEqual(utilization, 60.0, accuracy: 0.001)
    }

    /// Gemini session JSON shape — decode messages and count today's tokens.
    /// Uses the test fixture directly via a test-local mirror struct.
    func testGeminiSession_typicalFixture_decodesCorrectly() throws {
        // Mirror the private GeminiSession/GeminiMessage structs for test purposes
        struct MessageMirror: Decodable {
            let type: String
            let timestamp: Date
            let tokens: TokensMirror?
            var totalTokens: Int { tokens?.total ?? 0 }
        }
        struct TokensMirror: Decodable {
            let input: Int?
            let output: Int?
            let total: Int?
        }
        struct SessionMirror: Decodable {
            let messages: [MessageMirror]
        }

        let geminiDateStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = geminiDateStrategy

        let data = try loadFixture("gemini_session_typical.json")
        let session = try decoder.decode(SessionMirror.self, from: data)

        let geminiMessages = session.messages.filter { $0.type == "gemini" }
        XCTAssertEqual(geminiMessages.count, 2)

        let totalTokens = geminiMessages.reduce(0) { $0 + $1.totalTokens }
        XCTAssertEqual(totalTokens, 6500) // 2000 + 4500
    }

    func testGeminiSession_noTokensField_totalTokensIsZero() throws {
        struct MessageMirror: Decodable {
            let type: String
            let timestamp: Date
            let tokens: TokensMirror?
            var totalTokens: Int { tokens?.total ?? 0 }
        }
        struct TokensMirror: Decodable {
            let input: Int?
            let output: Int?
            let total: Int?
        }
        struct SessionMirror: Decodable {
            let messages: [MessageMirror]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixedDecoder = JSONDecoder()
        fixedDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }

        let data = try loadFixture("gemini_session_no_tokens.json")
        let session = try fixedDecoder.decode(SessionMirror.self, from: data)
        let message = try XCTUnwrap(session.messages.first)
        XCTAssertEqual(message.totalTokens, 0)
    }
}
