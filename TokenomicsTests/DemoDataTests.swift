import XCTest
@testable import Tokenomics

/// Tests that `DemoData` produces coherent fixture snapshots.
final class DemoDataTests: XCTestCase {

    // MARK: - Coverage

    /// Every ProviderId that `supportsUsageTracking` must have a snapshot in `allSnapshots`.
    func testAllSnapshots_coversEveryTrackableProvider() {
        let snapshots = DemoData.allSnapshots
        let trackable = ProviderId.allCases.filter(\.supportsUsageTracking)

        for providerId in trackable {
            XCTAssertNotNil(
                snapshots[providerId],
                "DemoData.allSnapshots is missing a snapshot for \(providerId.rawValue)"
            )
        }
    }

    /// Providers with `supportsUsageTracking == false` should not appear in `allSnapshots`.
    func testAllSnapshots_excludesUntrackedProviders() {
        let snapshots = DemoData.allSnapshots
        let untracked = ProviderId.allCases.filter { !$0.supportsUsageTracking }

        for providerId in untracked {
            XCTAssertNil(
                snapshots[providerId],
                "DemoData.allSnapshots unexpectedly contains a snapshot for untracked provider \(providerId.rawValue)"
            )
        }
    }

    // MARK: - Utilization Range

    /// All shortWindow utilization values must be in [0, 100].
    func testAllSnapshots_utilizationInValidRange() {
        for (id, snapshot) in DemoData.allSnapshots {
            XCTAssertGreaterThanOrEqual(snapshot.shortWindow.utilization, 0,
                "\(id.rawValue) shortWindow utilization below 0")
            XCTAssertLessThanOrEqual(snapshot.shortWindow.utilization, 100,
                "\(id.rawValue) shortWindow utilization above 100")

            if let long = snapshot.longWindow {
                XCTAssertGreaterThanOrEqual(long.utilization, 0,
                    "\(id.rawValue) longWindow utilization below 0")
                XCTAssertLessThanOrEqual(long.utilization, 100,
                    "\(id.rawValue) longWindow utilization above 100")
            }
        }
    }

    // MARK: - Visual State Spread

    /// There must be at least one snapshot at ≥ 90% (exercises warning / near-limit color).
    func testAllSnapshots_includesNearLimitProvider() {
        let hasNearLimit = DemoData.allSnapshots.values.contains { $0.shortWindow.utilization >= 90 }
        XCTAssertTrue(hasNearLimit, "Demo data must include at least one provider at ≥ 90% to exercise warning color")
    }

    /// There must be at least one snapshot at exactly 100% (exercises depleted state).
    func testAllSnapshots_includesMaxedProvider() {
        let hasMaxed = DemoData.allSnapshots.values.contains { $0.shortWindow.utilization == 100 }
        XCTAssertTrue(hasMaxed, "Demo data must include at least one provider at 100% to exercise the depleted state")
    }

    /// There must be at least one snapshot with a `sublabelOverride` (exercises remaining-only UI).
    func testAllSnapshots_includesRemainingOnlyProvider() {
        let hasRemaining = DemoData.allSnapshots.values.contains {
            $0.shortWindow.sublabelOverride != nil
        }
        XCTAssertTrue(hasRemaining, "Demo data must include at least one provider with a sublabelOverride to exercise remaining-only display")
    }

    // MARK: - Scaled Snapshots

    func testScaledSnapshots_clampsBelowZero() {
        let snapshots = DemoData.scaledSnapshots(utilization: -10)
        for (_, snapshot) in snapshots {
            XCTAssertEqual(snapshot.shortWindow.utilization, 0)
        }
    }

    func testScaledSnapshots_clampsAbove100() {
        let snapshots = DemoData.scaledSnapshots(utilization: 150)
        for (_, snapshot) in snapshots {
            XCTAssertEqual(snapshot.shortWindow.utilization, 100)
        }
    }

    func testScaledSnapshots_setsExactValue() {
        let snapshots = DemoData.scaledSnapshots(utilization: 50)
        for (_, snapshot) in snapshots {
            XCTAssertEqual(snapshot.shortWindow.utilization, 50)
            if let long = snapshot.longWindow {
                XCTAssertEqual(long.utilization, 50)
            }
        }
    }

    func testScaledSnapshots_preservesLabels() {
        // Call allSnapshots and scaledSnapshots together so both use the same
        // relative "now" — dates can't be compared since each call to futureDate()
        // is tied to the current moment, but labels are static strings.
        let original = DemoData.allSnapshots
        let scaled = DemoData.scaledSnapshots(utilization: 75)

        for (id, scaledSnapshot) in scaled {
            guard let originalSnapshot = original[id] else { continue }
            XCTAssertEqual(scaledSnapshot.shortWindow.label, originalSnapshot.shortWindow.label,
                "\(id.rawValue) shortWindow label changed after scaling")
            if let scaledLong = scaledSnapshot.longWindow, let originalLong = originalSnapshot.longWindow {
                XCTAssertEqual(scaledLong.label, originalLong.label,
                    "\(id.rawValue) longWindow label changed after scaling")
            }
        }
    }

    // MARK: - Plan Labels

    /// Every snapshot must have a non-empty planLabel (drives the plan badge).
    func testAllSnapshots_haveNonEmptyPlanLabel() {
        for (id, snapshot) in DemoData.allSnapshots {
            XCTAssertFalse(snapshot.planLabel.isEmpty,
                "\(id.rawValue) has an empty planLabel")
        }
    }

    // MARK: - Reset Dates

    /// All reset dates must be in the future so "Resets in Xh Ym" renders correctly.
    func testAllSnapshots_resetDatesAreInFuture() {
        let now = Date()
        for (id, snapshot) in DemoData.allSnapshots {
            XCTAssertGreaterThan(snapshot.shortWindow.resetsAt, now,
                "\(id.rawValue) shortWindow.resetsAt is in the past")
            if let long = snapshot.longWindow {
                XCTAssertGreaterThan(long.resetsAt, now,
                    "\(id.rawValue) longWindow.resetsAt is in the past")
            }
        }
    }
}
