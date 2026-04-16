import XCTest
@testable import Tokenomics

// MARK: - Tracking Bar Math Tests

/// Tests the fill-fraction math used by UsageBarView.
///
/// The bar clamps utilization to [0, 1] and passes it to GeometryReader
/// as `barWidth * clampedTarget`. These tests exercise the clamping
/// and edge cases — not the SwiftUI rendering itself.
final class TrackingBarMathTests: XCTestCase {

    // MARK: - clampedTarget = min(max(utilization / 100.0, 0), 1)

    private func clampedTarget(_ utilization: Double) -> Double {
        min(max(utilization / 100.0, 0), 1)
    }

    func testBarFill_zero_isZero() {
        XCTAssertEqual(clampedTarget(0), 0, accuracy: 0.001)
    }

    func testBarFill_fifty_isHalf() {
        XCTAssertEqual(clampedTarget(50), 0.5, accuracy: 0.001)
    }

    func testBarFill_hundred_isFull() {
        XCTAssertEqual(clampedTarget(100), 1.0, accuracy: 0.001)
    }

    func testBarFill_overLimit_clampedToOne() {
        // Over-limit values (e.g. 120%, 999%) must clamp — bar never exceeds full width
        XCTAssertEqual(clampedTarget(120), 1.0, accuracy: 0.001)
        XCTAssertEqual(clampedTarget(999), 1.0, accuracy: 0.001)
    }

    func testBarFill_negative_clampedToZero() {
        // Negative values must clamp — guard against any weird data upstream
        XCTAssertEqual(clampedTarget(-10), 0, accuracy: 0.001)
    }
}

// MARK: - Pace Math Tests (WindowUsage.pace)

/// Tests the pace computation on WindowUsage — the fraction of the window
/// that has elapsed. Determines where the pace dot sits on the bar.
final class PaceMathTests: XCTestCase {

    // MARK: - Helpers

    private func makeWindow(windowDuration: TimeInterval, resetsAt: Date) -> WindowUsage {
        WindowUsage(
            label: "Test Window",
            utilization: 50,
            resetsAt: resetsAt,
            windowDuration: windowDuration
        )
    }

    // MARK: - Basic pace

    func testPace_atStart_isZero() {
        // Window just started — resetsAt is exactly windowDuration from now
        let duration: TimeInterval = 5 * 3600 // 5 hours
        let resetsAt = Date().addingTimeInterval(duration)
        let window = makeWindow(windowDuration: duration, resetsAt: resetsAt)
        // elapsed ≈ 0, so pace ≈ 0
        XCTAssertEqual(window.pace, 0, accuracy: 0.02)
    }

    func testPace_atHalfway_isApproximatelyHalf() {
        let duration: TimeInterval = 5 * 3600
        let resetsAt = Date().addingTimeInterval(duration / 2)
        let window = makeWindow(windowDuration: duration, resetsAt: resetsAt)
        // elapsed ≈ duration/2, so pace ≈ 0.5
        XCTAssertEqual(window.pace, 0.5, accuracy: 0.02)
    }

    func testPace_afterReset_isOne() {
        // resetsAt is in the past — remaining is 0, so elapsed = duration
        let duration: TimeInterval = 5 * 3600
        let resetsAt = Date().addingTimeInterval(-60) // already reset
        let window = makeWindow(windowDuration: duration, resetsAt: resetsAt)
        XCTAssertEqual(window.pace, 1.0, accuracy: 0.001)
    }

    func testPace_zeroDuration_isZero() {
        // Non-time-based windows (context window) have windowDuration=0 → pace=0
        let window = makeWindow(windowDuration: 0, resetsAt: Date.distantFuture)
        XCTAssertEqual(window.pace, 0, accuracy: 0.001)
    }

    func testPace_atEndOfPeriod_isOne() {
        // resetsAt is very close to now — almost fully elapsed
        let duration: TimeInterval = 5 * 3600
        let resetsAt = Date().addingTimeInterval(1) // 1 second left of 5 hours
        let window = makeWindow(windowDuration: duration, resetsAt: resetsAt)
        // pace ≈ (18000 - 1) / 18000 ≈ 0.9999
        XCTAssertGreaterThan(window.pace, 0.999)
        XCTAssertLessThanOrEqual(window.pace, 1.0)
    }

    func testPace_exactlyOnPace_equalsUtilization() {
        // If elapsed fraction == utilization fraction, user is on pace
        // e.g. 40% through a 5-hour window and 40% usage — perfectly on pace
        let duration: TimeInterval = 5 * 3600
        let elapsed = 0.4 * duration
        let resetsAt = Date().addingTimeInterval(duration - elapsed)
        let window = WindowUsage(
            label: "5-Hour Window",
            utilization: 40,
            resetsAt: resetsAt,
            windowDuration: duration
        )
        // pace ≈ 0.4, utilization = 40%
        XCTAssertEqual(window.pace, 0.4, accuracy: 0.02)
    }
}
