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
        XCTAssertEqual(snap.planLabel, "Pro")
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

    // MARK: - Token-based billing (2026)

    /// Pro-style capped snapshot: string entitlement, percent_remaining drives the bar.
    func testTokenBased_cappedSnapshot_stringEntitlement_usesPercentRemaining() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"business","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{
           "chat":{"unlimited":true,"entitlement":"0"},
           "completions":{"unlimited":true,"entitlement":"0"},
           "premium_interactions":{"unlimited":false,"entitlement":"3900","percent_remaining":97.4,
             "overage_permitted":true,"has_quota":false,"token_based_billing":true}}}
        """)
        XCTAssertEqual(snap.shortWindow.label, "AI Credits")
        XCTAssertEqual(snap.shortWindow.utilization, 2.6, accuracy: 0.001)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "101 / 3,900 credits used")
        XCTAssertEqual(snap.planLabel, "Business")
        XCTAssertNotEqual(snap.shortWindow.resetsAt, Date.distantFuture)
    }

    /// credits_used has no denominator: percent and used come from percent_remaining / quota_remaining.
    func testTokenBased_creditsUsedIsNotDividedByEntitlement() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"individual_max","token_based_billing":true,"quota_reset_date_utc":"2026-12-01T00:00:00.000Z",
         "quota_snapshots":{"premium_interactions":{"unlimited":false,"entitlement":"20000",
           "credits_used":499,"quota_remaining":1501,"percent_remaining":7.5}}}
        """)
        XCTAssertEqual(snap.shortWindow.utilization, 92.5, accuracy: 0.001)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "18,499 / 20,000 credits used")
        XCTAssertEqual(snap.planLabel, "Max")
    }

    func testTokenBased_topLevelFlagOnly_fallsBackToRemainingCount() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"individual","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":1500,"remaining":1200,"unlimited":false}}}
        """)
        XCTAssertEqual(snap.shortWindow.label, "AI Credits")
        XCTAssertEqual(snap.shortWindow.utilization, 20, accuracy: 0.01)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "300 / 1,500 credits used")
    }

    func testTokenBased_unlimitedWithCreditsUsed_showsUsedCountNoFill() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"business","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"unlimited":true,"entitlement":0,"credits_used":31}}}
        """)
        XCTAssertEqual(snap.shortWindow.label, "AI Credits")
        XCTAssertEqual(snap.shortWindow.utilization, 0)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "31 credits used")
    }

    func testTokenBased_unlimitedNoCredits_showsUnlimited() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"enterprise","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":-1,"unlimited":false}}}
        """)
        XCTAssertEqual(snap.shortWindow.utilization, 0)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "Unlimited")
        XCTAssertEqual(snap.planLabel, "Enterprise")
    }

    func testMissingQuotaSnapshots_showsUnavailableNotZeroPercent() throws {
        let snap = try snapshot(from: #"{"copilot_plan":"business","token_based_billing":true}"#)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "Usage isn't available for this seat")
        XCTAssertEqual(snap.shortWindow.resetsAt, Date.distantFuture)
    }

    func testSubscriptionEnded_showsEndedState() throws {
        let snap = try snapshot(from: #"{"access_type_sku":"subscription_ended","copilot_plan":"individual"}"#)
        XCTAssertEqual(snap.planLabel, "Subscription ended")
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "Subscription ended")
    }

    func testResetPrecedence_snapshotQuotaResetAtWins() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"individual","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":1500,"percent_remaining":50,
           "unlimited":false,"quota_reset_at":1796083200}}}
        """)
        XCTAssertEqual(snap.shortWindow.resetsAt, Date(timeIntervalSince1970: 1_796_083_200))
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

    func testFreeTier_2026ResponseShape_skipsEmptyPremiumSnapshot() throws {
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

    func testPlanLabels() throws {
        func label(_ plan: String) throws -> String {
            let info = try JSONDecoder().decode(CopilotUserInfo.self, from: Data(#"{"copilot_plan":"\#(plan)"}"#.utf8))
            return info.planLabel
        }
        XCTAssertEqual(try label("individual"), "Pro")
        XCTAssertEqual(try label("individual_pro"), "Pro+")
        XCTAssertEqual(try label("individual_max"), "Max")
        XCTAssertEqual(try label("business"), "Business")
        XCTAssertEqual(try label("enterprise"), "Enterprise")
        XCTAssertEqual(try label("individual_edu"), "Edu")
    }

    func testFree_missingRemaining_usesQuotaRemainingThenPercent_neverFalse100() throws {
        let viaQuota = try snapshot(from: """
        {"access_type_sku":"free_limited_copilot","quota_reset_date":"2026-12-01",
         "quota_snapshots":{"chat":{"entitlement":200,"quota_remaining":150,"unlimited":false},
           "completions":{"entitlement":2000,"percent_remaining":75,"unlimited":false},
           "premium_interactions":{"entitlement":0,"unlimited":false}}}
        """)
        XCTAssertEqual(viaQuota.shortWindow.utilization, 25, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(viaQuota.longWindow).utilization, 25, accuracy: 0.01)

        let unknown = try snapshot(from: """
        {"access_type_sku":"free_limited_copilot","quota_reset_date":"2026-12-01",
         "quota_snapshots":{"chat":{"entitlement":200,"unlimited":false},
           "premium_interactions":{"entitlement":0,"unlimited":false}}}
        """)
        XCTAssertEqual(unknown.shortWindow.utilization, 0, accuracy: 0.01)
    }

    func testHugeOrInfiniteNumbers_doNotCrash() throws {
        let snap = try snapshot(from: """
        {"copilot_plan":"individual","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"entitlement":"1e400","quota_remaining":"inf",
           "percent_remaining":"nan","credits_used":"1e999","unlimited":false}}}
        """)
        XCTAssertEqual(snap.shortWindow.sublabelOverride, "Usage isn't available for this seat")

        let unlimited = try snapshot(from: """
        {"copilot_plan":"business","token_based_billing":true,"quota_reset_date":"2026-12-01",
         "quota_snapshots":{"premium_interactions":{"unlimited":true,"entitlement":0,"credits_used":"1e999"}}}
        """)
        XCTAssertEqual(unlimited.shortWindow.sublabelOverride, "0 credits used")
    }
}
