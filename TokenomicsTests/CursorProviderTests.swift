import XCTest
@testable import Tokenomics

/// Fixtures mirror openusage's CursorUnifiedAccountTests (2026-11-15).
final class CursorProviderTests: XCTestCase {

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let unifiedSummary = """
    {"billingCycleEnd":"2026-12-01T00:00:00.000Z","billingCycleStart":"2026-11-01T00:00:00.000Z","isUnlimited":false,
     "individualUsage":{"onDemand":{"enabled":false,"used":0},"plan":{"enabled":true,"limit":55395,"remaining":55395,"used":0}},
     "limitType":"user","membershipType":"unified_ultra","teamUsage":{}}
    """

    func testUnifiedAccount_showsOneWeeklyPool() throws {
        let summary: CursorUsageSummary = try decode(unifiedSummary)
        XCTAssertTrue(summary.isUnified)
        let usage: CursorCurrentPeriodUsage = try decode("""
        {"billingCycleEnd":"1795333076119","enabled":true,
         "planUsage":{"autoPercentUsed":0.1083130246412131,"totalPercentUsed":0.1083130246412131},
         "spendLimitUsage":{"limitType":"user"}}
        """)
        let plan: CursorPlanInfoResponse = try decode("""
        {"isMerged":true,"planInfo":{"billingCycleEnd":"1797320277830",
         "includedUsagePeriod":"INCLUDED_USAGE_PERIOD_WEEKLY","includedUsageResetsAt":"1795333076119","planName":"Ultra"}}
        """)
        let snap = CursorProvider.mapUnifiedSnapshot(summary: summary, usage: usage, plan: plan)
        XCTAssertEqual(snap.shortWindow.label, "Weekly Usage")
        XCTAssertEqual(snap.shortWindow.utilization, 0.1083, accuracy: 0.0001)
        XCTAssertEqual(snap.shortWindow.resetsAt, Date(timeIntervalSince1970: 1_795_333_076.119))
        XCTAssertEqual(snap.shortWindow.windowDuration, 7 * 24 * 3600)
        XCTAssertNil(snap.longWindow)
        XCTAssertEqual(snap.planLabel, "Ultra")
    }

    func testUnifiedAccount_ignoresStaleMonthlyNumbers() throws {
        let summary: CursorUsageSummary = try decode(unifiedSummary)
        let usage: CursorCurrentPeriodUsage = try decode(#"{"planUsage":{"totalPercentUsed":42}}"#)
        let plan: CursorPlanInfoResponse = try decode(#"{"isMerged":true,"planInfo":{"includedUsageResetsAt":"1795333076119"}}"#)
        let snap = CursorProvider.mapUnifiedSnapshot(summary: summary, usage: usage, plan: plan)
        XCTAssertEqual(snap.shortWindow.utilization, 42, accuracy: 0.001)
        XCTAssertNotEqual(snap.shortWindow.label, "Premium Requests")
    }

    func testLegacyAccount_keepsMonthlyPremiumRequests() throws {
        let summary: CursorUsageSummary = try decode("""
        {"billingCycleEnd":"2026-12-01T00:00:00.000Z","billingCycleStart":"2026-11-01T00:00:00.000Z",
         "membershipType":"pro","individualUsage":{"plan":{"enabled":true,"used":100,"limit":500,"totalPercentUsed":20}}}
        """)
        XCTAssertFalse(summary.isUnified)
        let snap = CursorProvider.mapToSnapshot(summary)
        XCTAssertEqual(snap.shortWindow.label, "Premium Requests")
        XCTAssertEqual(snap.shortWindow.utilization, 20, accuracy: 0.001)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "100 / 500 used")
        XCTAssertEqual(snap.planLabel, "Pro")
    }
}
