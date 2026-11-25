import XCTest
@testable import Tokenomics

/// Fixture matches Runway's OpenAPI spec for `GET /v1/organization`.
final class RunwayProviderTests: XCTestCase {

    private let fixture = """
    {"tier":{"maxMonthlyCreditSpend":1000,"models":{"gen4_turbo":{"maxConcurrentGenerations":2,"maxDailyGenerations":50}}},
     "creditBalance":2400,
     "usage":{"models":{"gen4_turbo":{"dailyGenerations":3}}}}
    """

    func testDecodesCreditBalanceFromOrganizationResponse() throws {
        let org = try RunwayProvider.decodeOrganization(Data(fixture.utf8))
        XCTAssertEqual(org.creditBalance, 2400)
    }

    func testOldCreditsShape_doesNotDecode() {
        let old = #"{"credits":{"used":1,"total":2}}"#
        XCTAssertThrowsError(try RunwayProvider.decodeOrganization(Data(old.utf8)))
    }

    func testFirstRun_seedsCycle_noResetDate() {
        var history = BalanceHistory()
        RunwayProvider.recordBalance(2400, in: &history)
        let snap = RunwayProvider.mapToSnapshot(currentBalance: 2400, history: history)
        XCTAssertEqual(snap.shortWindow.label, "Credits")
        XCTAssertEqual(snap.shortWindow.utilization, 0, accuracy: 0.001)
        XCTAssertEqual(snap.shortWindow.resetsAt, Date.distantFuture)
        XCTAssertTrue(snap.shortWindow.sublabelOverride?.hasSuffix("credits remaining") == true)
        XCTAssertEqual(snap.creditsBalance, 2400.formatted())
    }

    func testUsageSinceTopUp_andTopUpDetection() {
        var history = BalanceHistory()
        RunwayProvider.recordBalance(1000, in: &history)
        RunwayProvider.recordBalance(750, in: &history)
        var snap = RunwayProvider.mapToSnapshot(currentBalance: 750, history: history)
        XCTAssertEqual(snap.shortWindow.utilization, 25, accuracy: 0.001)

        // Balance rises: new cycle, usage resets to 0.
        RunwayProvider.recordBalance(2000, in: &history)
        snap = RunwayProvider.mapToSnapshot(currentBalance: 2000, history: history)
        XCTAssertEqual(snap.shortWindow.utilization, 0, accuracy: 0.001)
        XCTAssertEqual(history.cycleStartBalance, 2000)
    }
}
