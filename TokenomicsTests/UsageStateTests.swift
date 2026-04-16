import XCTest
@testable import Tokenomics

// MARK: - UsageState Init Tests

/// Pins the threshold boundaries for UsageState so any accidental
/// changes to the 70/90/100 breakpoints are caught immediately.
final class UsageStateTests: XCTestCase {

    // MARK: - Boundary Tests

    func testUsageState_zero_isHealthy() {
        XCTAssertEqual(UsageState(utilization: 0), .healthy)
    }

    func testUsageState_belowCaution_isHealthy() {
        XCTAssertEqual(UsageState(utilization: 69.9), .healthy)
    }

    func testUsageState_atCautionBoundary_isCaution() {
        XCTAssertEqual(UsageState(utilization: 70), .caution)
    }

    func testUsageState_midCaution_isCaution() {
        XCTAssertEqual(UsageState(utilization: 80), .caution)
    }

    func testUsageState_atWarningBoundary_isWarning() {
        XCTAssertEqual(UsageState(utilization: 90), .warning)
    }

    func testUsageState_midWarning_isWarning() {
        XCTAssertEqual(UsageState(utilization: 95), .warning)
    }

    func testUsageState_atHundred_isDepleted() {
        XCTAssertEqual(UsageState(utilization: 100), .depleted)
    }

    func testUsageState_overHundred_isDepleted() {
        XCTAssertEqual(UsageState(utilization: 150), .depleted)
    }
}

// MARK: - UsageState Equatable

extension UsageState: Equatable {
    public static func == (lhs: UsageState, rhs: UsageState) -> Bool {
        switch (lhs, rhs) {
        case (.healthy, .healthy): return true
        case (.caution, .caution): return true
        case (.warning, .warning): return true
        case (.depleted, .depleted): return true
        case (.error, .error): return true
        case (.loading, .loading): return true
        case (.unauthenticated, .unauthenticated): return true
        default: return false
        }
    }
}
