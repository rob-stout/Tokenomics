import XCTest
@testable import Tokenomics

/// Representative `copilot_internal/user` payloads for free and paid plans.
final class CopilotProviderTests: XCTestCase {

    private func snapshot(from json: String) throws -> ProviderUsageSnapshot {
        let info = try JSONDecoder().decode(CopilotUserInfo.self, from: Data(json.utf8))
        return CopilotProvider.mapToSnapshot(info)
    }

    func testFreeTier_keepsChatAndCompletionsBars() throws {
        let snap = try snapshot(from: """
        {"login":"a","access_type_sku":"free_limited_copilot","copilot_plan":"free",
         "limited_user_quotas":{"chat":30,"completions":1500},
         "monthly_quotas":{"chat":50,"completions":2000},
         "limited_user_reset_date":"2026-12-01"}
        """)
        XCTAssertEqual(snap.shortWindow.label, "Chat")
        XCTAssertEqual(snap.shortWindow.utilization, 40, accuracy: 0.01)
        XCTAssertEqual(snap.longWindow?.label, "Completions")
        XCTAssertEqual(try XCTUnwrap(snap.longWindow).utilization, 25, accuracy: 0.01)
        XCTAssertEqual(snap.planLabel, "Free")
    }

    func testPaidPlan_showsPremiumRequests() throws {
        let snap = try snapshot(from: """
        {"login":"a","copilot_plan":"individual","access_type_sku":"copilot_for_individual",
         "quota_reset_date":"2026-12-01","quota_reset_date_utc":"2026-12-01T00:00:00.000Z",
         "quota_snapshots":{
           "chat":{"entitlement":0,"remaining":0,"percent_remaining":100.0,"unlimited":true},
           "completions":{"entitlement":0,"remaining":0,"percent_remaining":100.0,"unlimited":true},
           "premium_interactions":{"entitlement":300,"remaining":225,"percent_remaining":75.0,
             "overage_count":0,"overage_permitted":true,"unlimited":false}}}
        """)
        XCTAssertEqual(snap.shortWindow.label, "Premium Requests")
        XCTAssertEqual(snap.shortWindow.utilization, 25, accuracy: 0.01)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "75 / 300 used")
        XCTAssertNil(snap.longWindow)
        XCTAssertEqual(snap.planLabel, "Individual")
        XCTAssertNotEqual(snap.shortWindow.resetsAt, Date.distantFuture)
    }

    func testPaidPlan_unlimitedPremium_showsZeroAndUnlimited() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"enterprise","quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":0,"remaining":0,"percent_remaining":100.0,"unlimited":true}}}
        """)
        XCTAssertEqual(snap.shortWindow.utilization, 0)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "Unlimited")
    }

    func testPaidPlan_overage_isNotClampedBelowEntitlement() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"business","quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":0,"percent_remaining":0.0,"unlimited":false}}}
        """)
        XCTAssertEqual(snap.shortWindow.utilization, 100, accuracy: 0.01)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "300 / 300 used")
    }

    func testTokenBasedPaidPlan_showsAICredits() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"individual","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":1500,"remaining":1100,
           "percent_remaining":73.3,"unlimited":false,"token_based_billing":true,"credits_used":400}}}
        """)
        XCTAssertEqual(snap.shortWindow.label, "AI Credits")
        XCTAssertEqual(snap.shortWindow.utilization, 400.0 / 1500.0 * 100, accuracy: 0.01)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "400 / 1500 used")
        XCTAssertNotEqual(snap.shortWindow.resetsAt, Date.distantFuture)
    }

    func testTokenBased_topLevelFlagOnly_withoutCreditsUsed_fallsBackToRemaining() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"individual","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":1500,"remaining":1200,"unlimited":false}}}
        """)
        XCTAssertEqual(snap.shortWindow.label, "AI Credits")
        XCTAssertEqual(snap.shortWindow.utilization, 20, accuracy: 0.01)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "300 / 1500 used")
    }

    func testLegacyPremiumRequests_snapshotFlagFalse_keepsPremiumRequests() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"individual","token_based_billing":false,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":225,
           "percent_remaining":75.0,"unlimited":false,"token_based_billing":false}}}
        """)
        XCTAssertEqual(snap.shortWindow.label, "Premium Requests")
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "75 / 300 used")
    }

    func testFreeTier_2026ResponseShape_usesChatAndCompletionsSnapshots() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"individual","access_type_sku":"free_limited_copilot","token_based_billing":true,
         "quota_reset_date":"2026-12-01","quota_reset_date_utc":"2026-12-01T00:00:00.000Z",
         "quota_snapshots":{
           "chat":{"entitlement":200,"remaining":150,"unlimited":false,"has_quota":true,"token_based_billing":true,"credits_used":0},
           "completions":{"entitlement":2000,"remaining":1500,"unlimited":false,"has_quota":true},
           "premium_interactions":{"entitlement":0,"remaining":0,"unlimited":false,"has_quota":false}}}
        """)
        XCTAssertEqual(snap.shortWindow.label, "Chat")
        XCTAssertEqual(snap.shortWindow.utilization, 25, accuracy: 0.01)
        XCTAssertEqual(snap.longWindow?.label, "Completions")
        XCTAssertEqual(snap.planLabel, "Free")
        XCTAssertNotEqual(snap.shortWindow.resetsAt, Date.distantFuture)
    }

    func testTokenBased_unlimited_showsUnlimited() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"enterprise","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":0,"remaining":0,"unlimited":true,"token_based_billing":true}}}
        """)
        XCTAssertEqual(snap.shortWindow.utilization, 0)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "Unlimited")
    }
}
