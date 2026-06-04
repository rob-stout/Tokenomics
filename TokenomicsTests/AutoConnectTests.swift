import XCTest
@testable import Tokenomics

/// Regression tests for the onboarding auto-connect explainer.
///
/// Two guarantees are protected here:
///   1. **Faithful checkoff** — `ConnectorContainer.applyAutoConnect` only checks
///      off steps for providers that genuinely connected, never invents a checked
///      step, and reports `allDone` correctly. (We must never show a checkmark for
///      something that didn't actually connect.)
///   2. **Digestible timing floor** — `AutoConnectStep.totalDurationMS` never lets
///      the screen advance before the 2s minimum, regardless of provider count, so
///      the moment is perceptible and never "flashes by".
final class AutoConnectTests: XCTestCase {

    // MARK: - Fixtures

    private func step(_ number: Int, _ target: ProviderId) -> SetupPlan.Step {
        SetupPlan.Step(
            number: number,
            title: "Step \(number)",
            description: "",
            timeEstimate: "~5 sec",
            covers: nil,
            launchTarget: target
        )
    }

    /// Extension batch (chatgpt) + two CLI steps (claude, cursor).
    private func mixedPlan() -> SetupPlan {
        SetupPlan(
            providerCount: 3,
            stepCount: 3,
            estimatedDuration: "about a minute",
            steps: [step(1, .chatgpt), step(2, .claude), step(3, .cursor)]
        )
    }

    // MARK: - Checkoff

    func testConnectedProvidersCheckOffTheirSteps() {
        let result = ConnectorContainer.applyAutoConnect(
            plan: mixedPlan(),
            alreadyCompleted: [],
            connected: [.claude, .cursor]
        )
        XCTAssertEqual(result.completed, [2, 3])
        // The extension step (1) still needs the user → not all done.
        XCTAssertFalse(result.allDone)
    }

    func testConnectedProviderNotInPlanIsIgnored() {
        // .gemini is connected on the machine but the user didn't select it, so
        // it isn't a step. It must NOT check anything off.
        let result = ConnectorContainer.applyAutoConnect(
            plan: mixedPlan(),
            alreadyCompleted: [],
            connected: [.claude, .gemini]
        )
        XCTAssertEqual(result.completed, [2])
        XCTAssertFalse(result.allDone)
    }

    func testAllStepsConnectedReportsAllDone() {
        let plan = SetupPlan(
            providerCount: 2, stepCount: 2, estimatedDuration: "under a minute",
            steps: [step(1, .claude), step(2, .cursor)]
        )
        let result = ConnectorContainer.applyAutoConnect(
            plan: plan, alreadyCompleted: [], connected: [.claude, .cursor]
        )
        XCTAssertEqual(result.completed, [1, 2])
        XCTAssertTrue(result.allDone)
    }

    func testNothingConnectedLeavesPlanUntouched() {
        let result = ConnectorContainer.applyAutoConnect(
            plan: mixedPlan(), alreadyCompleted: [], connected: []
        )
        XCTAssertTrue(result.completed.isEmpty)
        XCTAssertFalse(result.allDone)
    }

    func testPreservesAlreadyCompletedSteps() {
        let result = ConnectorContainer.applyAutoConnect(
            plan: mixedPlan(), alreadyCompleted: [1], connected: [.claude]
        )
        XCTAssertEqual(result.completed, [1, 2])
    }

    func testEmptyPlanIsNotAllDone() {
        let empty = SetupPlan(providerCount: 0, stepCount: 0, estimatedDuration: "", steps: [])
        let result = ConnectorContainer.applyAutoConnect(
            plan: empty, alreadyCompleted: [], connected: []
        )
        XCTAssertFalse(result.allDone)
    }

    // MARK: - Timing floor

    func testTotalDurationNeverDropsBelowFloor() {
        // Whatever the count, the screen stays up at least the 2s floor.
        for count in 1...8 {
            XCTAssertGreaterThanOrEqual(
                AutoConnectStep.totalDurationMS(count: count), 2000,
                "count \(count) advanced before the 2s floor"
            )
        }
    }

    func testTotalDurationStaysBounded() {
        // Larger sets compress the stagger so it never drags on.
        XCTAssertLessThanOrEqual(AutoConnectStep.totalDurationMS(count: 5), 2700)
    }

    func testLargerSetsUseTighterStagger() {
        XCTAssertEqual(AutoConnectStep.staggerMS(forCount: 3), 300)
        XCTAssertEqual(AutoConnectStep.staggerMS(forCount: 4), 220)
    }
}
