import XCTest
@testable import Tokenomics

// MARK: - UsageData Plan Inference Tests

final class UsageDataTests: XCTestCase {

    // MARK: - Helpers

    private func makeUsagePeriod(utilization: Double = 0.5) -> UsagePeriod {
        UsagePeriod(utilization: utilization, resetsAt: Date().addingTimeInterval(3600))
    }

    private func makeExtraUsage() -> ExtraUsage {
        ExtraUsage(isEnabled: true, monthlyLimit: 5000, usedCredits: 1000, utilization: 0.2)
    }

    // MARK: - Plan Inference

    /// extraUsage present → Max plan (even if no per-model fields)
    func testPlanInference_extraUsage_returnsMax() {
        let data = UsageData(
            fiveHour: makeUsagePeriod(),
            sevenDay: makeUsagePeriod(),
            sevenDayOauthApps: nil,
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            sevenDayCowork: nil,
            extraUsage: makeExtraUsage()
        )
        XCTAssertEqual(data.inferredPlan, .max)
    }

    /// extraUsage present alongside per-model fields → still Max (extraUsage wins)
    func testPlanInference_extraUsageWithPerModelFields_returnsMax() {
        let data = UsageData(
            fiveHour: makeUsagePeriod(),
            sevenDay: makeUsagePeriod(),
            sevenDayOauthApps: nil,
            sevenDayOpus: makeUsagePeriod(),
            sevenDaySonnet: makeUsagePeriod(),
            sevenDayCowork: nil,
            extraUsage: makeExtraUsage()
        )
        XCTAssertEqual(data.inferredPlan, .max)
    }

    /// sevenDayOpus present, no extraUsage → Pro
    func testPlanInference_sevenDayOpus_returnsPro() {
        let data = UsageData(
            fiveHour: makeUsagePeriod(),
            sevenDay: makeUsagePeriod(),
            sevenDayOauthApps: nil,
            sevenDayOpus: makeUsagePeriod(),
            sevenDaySonnet: nil,
            sevenDayCowork: nil,
            extraUsage: nil
        )
        XCTAssertEqual(data.inferredPlan, .pro)
    }

    /// sevenDaySonnet present, no extraUsage → Pro
    func testPlanInference_sevenDaySonnet_returnsPro() {
        let data = UsageData(
            fiveHour: makeUsagePeriod(),
            sevenDay: makeUsagePeriod(),
            sevenDayOauthApps: nil,
            sevenDayOpus: nil,
            sevenDaySonnet: makeUsagePeriod(),
            sevenDayCowork: nil,
            extraUsage: nil
        )
        XCTAssertEqual(data.inferredPlan, .pro)
    }

    /// No per-model fields, no extraUsage → Free
    func testPlanInference_noExtras_returnsFree() {
        let data = UsageData(
            fiveHour: makeUsagePeriod(),
            sevenDay: makeUsagePeriod(),
            sevenDayOauthApps: nil,
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            sevenDayCowork: nil,
            extraUsage: nil
        )
        XCTAssertEqual(data.inferredPlan, .free)
    }

    // MARK: - Dollar Formatting

    func testExtraUsage_monthlyLimitFormatted_convertsCentsToUSD() {
        let extra = ExtraUsage(isEnabled: true, monthlyLimit: 5000, usedCredits: nil, utilization: nil)
        XCTAssertEqual(extra.monthlyLimitFormatted, "$50.00")
    }

    func testExtraUsage_usedCreditsFormatted_convertsCentsToUSD() {
        let extra = ExtraUsage(isEnabled: true, monthlyLimit: nil, usedCredits: 1234, utilization: nil)
        XCTAssertEqual(extra.usedCreditsFormatted, "$12.34")
    }

    func testExtraUsage_nilValues_returnZeroDollars() {
        let extra = ExtraUsage(isEnabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
        XCTAssertEqual(extra.monthlyLimitFormatted, "$0.00")
        XCTAssertEqual(extra.usedCreditsFormatted, "$0.00")
    }

    // MARK: - JSON Decoding with Custom Date Formatter

    /// Verifies the decoder handles fractional-second ISO8601 dates from the real API
    func testUsagePeriod_decodesISO8601WithFractionalSeconds() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 0.75,
                "resets_at": "2026-02-25T20:00:00.849139+00:00"
            },
            "seven_day": {
                "utilization": 0.3,
                "resets_at": "2026-03-01T00:00:00.000000+00:00"
            }
        }
        """.data(using: .utf8)!

        let decoder = makeDecoder()
        let data = try decoder.decode(UsageData.self, from: json)
        XCTAssertEqual(data.fiveHour.utilization, 0.75, accuracy: 0.001)
        XCTAssertNil(data.extraUsage)
    }

    /// Verifies fallback to non-fractional ISO8601 dates
    func testUsagePeriod_decodesISO8601WithoutFractionalSeconds() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 0.5,
                "resets_at": "2026-02-25T20:00:00+00:00"
            },
            "seven_day": {
                "utilization": 0.5,
                "resets_at": "2026-03-01T00:00:00+00:00"
            }
        }
        """.data(using: .utf8)!

        let decoder = makeDecoder()
        let data = try decoder.decode(UsageData.self, from: json)
        XCTAssertEqual(data.fiveHour.utilization, 0.5, accuracy: 0.001)
    }

    /// Malformed date string must throw rather than silently succeed
    func testUsagePeriod_malformedDate_throws() {
        let json = """
        {
            "five_hour": {
                "utilization": 0.5,
                "resets_at": "not-a-date"
            },
            "seven_day": {
                "utilization": 0.5,
                "resets_at": "not-a-date"
            }
        }
        """.data(using: .utf8)!

        let decoder = makeDecoder()
        XCTAssertThrowsError(try decoder.decode(UsageData.self, from: json))
    }

    // MARK: - Private

    /// Replicates the decoder configuration from UsageService so tests run without
    /// instantiating the actor (which would require a running URLSession).
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
        }
        return decoder
    }
}
