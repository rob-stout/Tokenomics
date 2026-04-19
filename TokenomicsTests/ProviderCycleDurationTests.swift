import XCTest
@testable import Tokenomics

// MARK: - RunwayProvider Cycle Duration Tests

/// Regression tests for RunwayProvider.cycleDuration(for:).
/// Guards the 30-day fixed window and the distantFuture → 0 sentinel path.
final class RunwayProviderCycleDurationTests: XCTestCase {

    /// Valid reset date → exactly 30 days in seconds.
    func testCycleDuration_withValidResetDate_is30Days() {
        let resetsAt = Date().addingTimeInterval(7 * 24 * 3600) // arbitrary future date
        XCTAssertEqual(RunwayProvider.cycleDuration(for: resetsAt), 30 * 24 * 3600, accuracy: 0.001)
    }

    /// distantFuture (nil resetsAt from API) → 0, so pace dot hides honestly.
    func testCycleDuration_withDistantFuture_isZero() {
        XCTAssertEqual(RunwayProvider.cycleDuration(for: .distantFuture), 0, accuracy: 0.001)
    }
}

// MARK: - ElevenLabsProvider Cycle Duration Tests

/// Regression tests for ElevenLabsProvider.cycleDuration(for:).
/// Guards the 31-day worst-case window and the distantFuture → 0 sentinel path.
final class ElevenLabsProviderCycleDurationTests: XCTestCase {

    /// Valid reset date → exactly 31 days in seconds.
    func testCycleDuration_withValidResetDate_is31Days() {
        let resetsAt = Date().addingTimeInterval(14 * 24 * 3600) // arbitrary future date
        XCTAssertEqual(ElevenLabsProvider.cycleDuration(for: resetsAt), 31 * 24 * 3600, accuracy: 0.001)
    }

    /// distantFuture (nil nextCharacterCountResetUnix from API) → 0.
    func testCycleDuration_withDistantFuture_isZero() {
        XCTAssertEqual(ElevenLabsProvider.cycleDuration(for: .distantFuture), 0, accuracy: 0.001)
    }
}

// MARK: - CursorProvider Cycle Duration Tests

/// Regression tests for CursorProvider.cycleDuration(start:end:).
/// Guards the actual-span calculation and all nil-input sentinel paths.
final class CursorProviderCycleDurationTests: XCTestCase {

    private let thirtyDays: TimeInterval = 30 * 24 * 3600

    /// Both endpoints present → duration equals the real calendar span.
    func testCycleDuration_withBothEndpoints_isCorrectSpan() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(thirtyDays)
        XCTAssertEqual(CursorProvider.cycleDuration(start: start, end: end), thirtyDays, accuracy: 0.001)
    }

    /// nil start → 0 (pace would be meaningless without a cycle anchor).
    func testCycleDuration_nilStart_isZero() {
        let end = Date().addingTimeInterval(thirtyDays)
        XCTAssertEqual(CursorProvider.cycleDuration(start: nil, end: end), 0, accuracy: 0.001)
    }

    /// nil end → 0 (no billing cycle end means no window to track against).
    func testCycleDuration_nilEnd_isZero() {
        let start = Date()
        XCTAssertEqual(CursorProvider.cycleDuration(start: start, end: nil), 0, accuracy: 0.001)
    }

    /// Both nil → 0.
    func testCycleDuration_bothNil_isZero() {
        XCTAssertEqual(CursorProvider.cycleDuration(start: nil, end: nil), 0, accuracy: 0.001)
    }
}
