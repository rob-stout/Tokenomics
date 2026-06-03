import SwiftUI
import os

/// Drives one provider's connector flow. Owns the polling timer that re-checks
/// the connector's state machine, marshals state from the provider's actor back
/// to the main actor for SwiftUI, and manages post-connection chaining
/// (Add another provider / I'm all set).
@MainActor
final class ConnectorViewModel: ObservableObject, Identifiable {
    /// Stable identifier so SwiftUI's `.sheet(item:)` can uniquely track this VM.
    let id = UUID()

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ConnectorViewModel")

    // MARK: - Published state

    @Published private(set) var step: ConnectorStep = .detecting

    /// Display name shown in the connector header.
    let providerName: String

    let providerId: ProviderId

    let pipelineKind: ConnectorPipelineKind

    /// Stepper segment labels, read once from the connector at init.
    /// Stored so `stepperItems` stays a simple computed property on MainActor.
    private let labels: (step1: String, step2: String, step3: String, step4: String)

    // MARK: - Stepper

    /// Maps the current step to the 4-segment onboarding stepper items shown
    /// across the top of every connector screen. Returns an empty array for
    /// steps that show no stepper (failed, waitingForExternalApp).
    var stepperItems: [OnboardingStepperItem] {
        typealias Item = OnboardingStepperItem
        typealias S = OnboardingStepperItem.State
        let c: S = .completed; let a: S = .active; let u: S = .upcoming
        let l1 = labels.step1; let l2 = labels.step2
        let l3 = labels.step3; let l4 = labels.step4
        switch step {
        case .detecting:
            // Checking the user's Mac for the prerequisites this provider needs.
            return [Item(label: l1, state: a), Item(label: l2, state: u),
                    Item(label: l3, state: u), Item(label: l4, state: u)]
        case .needsAction:
            // All prereqs are present — only sign-in remains. The next user
            // action is the OAuth handoff, so step 3 (Signing in) is active.
            // Steps 1+2 are complete because detection found everything installed.
            return [Item(label: l1, state: c), Item(label: l2, state: c),
                    Item(label: l3, state: a), Item(label: l4, state: u)]
        case .confirmingInstall, .installingDependency, .installing,
             .openProviderSite:
            // Step 2 active: installing tools / opening provider site for API key.
            return [Item(label: l1, state: c), Item(label: l2, state: a),
                    Item(label: l3, state: u), Item(label: l4, state: u)]
        case .pasteAPIKey:
            // Step 3 active: pasting the API key.
            return [Item(label: l1, state: c), Item(label: l2, state: c),
                    Item(label: l3, state: a), Item(label: l4, state: u)]
        case .previewExternalSteps, .awaitingOAuth, .awaitingUserConfirm, .awaitingExternalAuth:
            return [Item(label: l1, state: c), Item(label: l2, state: c),
                    Item(label: l3, state: a), Item(label: l4, state: u)]
        case .connected:
            return [Item(label: l1, state: c), Item(label: l2, state: c),
                    Item(label: l3, state: c), Item(label: l4, state: a)]
        case .waitingForExternalApp:
            // Pattern D (Cursor): stepper is visible, step 2 ("Installing Cursor") stays active
            // while we poll for the bundle + sign-in.
            return [Item(label: l1, state: c), Item(label: l2, state: a),
                    Item(label: l3, state: u), Item(label: l4, state: u)]
        case .skipped:
            // Skipped is transient — the VM fires the outcome callback and the
            // view is dismissed before the stepper is painted. Return empty.
            return []

        case .failed(let error):
            // Keep the stepper visible on failure so users can see which step failed.
            // Infer the failed step from the error type — avoids storing history.
            let e: S = .error
            switch error {
            case .cliInstallFailed, .homebrewInstallCancelled,
                 .homebrewNotReachable, .caskInstallFailed, .missingPrerequisite,
                 .permissionDenied:
                // Step 2 (Installing) failed
                return [Item(label: l1, state: c), Item(label: l2, state: e),
                        Item(label: l3, state: u), Item(label: l4, state: u)]
            case .oauthCancelled, .oauthFailed, .detectionTimeout,
                 .automationPermissionDenied, .appNotFound:
                // Step 3 (Signing in) failed
                return [Item(label: l1, state: c), Item(label: l2, state: c),
                        Item(label: l3, state: e), Item(label: l4, state: u)]
            default:
                // Unknown/keychain — show step 1 as error (detection phase)
                return [Item(label: l1, state: e), Item(label: l2, state: u),
                        Item(label: l3, state: u), Item(label: l4, state: u)]
            }
        }
    }

    // MARK: - Outcome

    /// Emitted when the user chooses what to do after connecting.
    enum Outcome {
        /// User wants to connect another provider next.
        case addAnother
        /// User is done with onboarding.
        case allSet
        /// User skipped this step — orchestrator routes around it.
        case skipped
    }

    private let onOutcome: (Outcome) -> Void

    // MARK: - Internal

    private let connector: any ProviderConnector
    private var pollingTask: Task<Void, Never>?

    /// Polling cadence while detection / install / OAuth is in progress.
    private static let pollInterval: TimeInterval = 1.5

    // No static stuckThreshold — per-state thresholds are computed by stuckThreshold(for:).

    // MARK: - Init

    init(connector: any ProviderConnector,
         onOutcome: @escaping (Outcome) -> Void) {
        self.connector = connector
        self.providerId = connector.id
        self.providerName = connector.id.displayName
        self.pipelineKind = connector.pipelineKind
        // nonisolated — safe to read directly without await
        self.labels = connector.stepperLabels
        self.onOutcome = onOutcome
    }

    // MARK: - Lifecycle

    /// Call from `.onAppear`. Kicks off the detection / polling loop.
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    /// Call from `.onDisappear` so the polling task stops.
    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - User actions

    /// Tap on the primary CTA — kick off whatever the connector needs (open
    /// download URL, start OAuth, run hidden install, etc.) and re-poll.
    func tappedPrimary() {
        Task { [connector] in
            await connector.performPrimaryAction()
        }
        // Force an immediate state refresh — don't wait for the next poll tick.
        Task { [weak self] in
            guard let self else { return }
            let current = await self.connector.currentStep()
            self.step = current
        }
    }

    /// Tap on the secondary cancel button.
    func tappedCancel() {
        Task { [connector] in
            await connector.cancel()
        }
    }

    /// Tap on "Continue" in the `.confirmingInstall` step.
    func tappedConfirmInstall() {
        Task { [connector] in
            await connector.confirmInstall()
        }
    }

    /// Tap on "I already have this" in the `.confirmingInstall` step.
    func tappedSkipInstall() {
        Task { [connector] in
            await connector.skipInstall()
        }
        // Immediately show detecting so the UI doesn't stay on the confirm screen.
        step = .detecting
    }

    /// Tap Continue in `.previewExternalSteps` — connector advances its internal
    /// phase (e.g. Window 3 → Window 4 → opens Terminal → Window 5).
    func tappedAdvancePreview() {
        Task { [connector] in
            await connector.advancePreview()
        }
        Task { [weak self] in
            guard let self else { return }
            let current = await self.connector.currentStep()
            self.step = current
        }
    }

    /// Tap "I'm signed in — check now" in `.awaitingExternalAuth` — kicks the
    /// polling loop awake immediately instead of waiting for the next tick.
    func tappedRecheck() {
        Task { [weak self] in
            guard let self else { return }
            let current = await self.connector.currentStep()
            self.step = current
        }
    }

    /// Step view's Back tapped on a screen that has a meaningful previous
    /// step within the connector's sub-flow (e.g. Paste API key → Get API key).
    /// Delegates to the connector to transition its phase; polling picks up
    /// the change and the UI routes to the previous screen on the next tick.
    func tappedBackOneStep() {
        Task { [connector, weak self] in
            await connector.goBackOneStep()
            guard let self else { return }
            let current = await self.connector.currentStep()
            self.step = current
        }
    }

    /// Submits an API key from the `.pasteAPIKey` step.
    /// Calls the connector's `submitAPIKey(_:)`, then forces a state refresh.
    func tappedSubmitAPIKey(_ key: String) {
        Task { [connector, weak self] in
            _ = await connector.submitAPIKey(key)
            guard let self else { return }
            let current = await self.connector.currentStep()
            self.step = current
        }
    }

    /// Recovery for `.permissionDenied` errors: clears the npm cache first,
    /// then restarts detection. The cache clear resolves bad ownership left
    /// by a prior failed install before retrying.
    func tappedPermissionDeniedRecovery() {
        Task { [connector, weak self] in
            await connector.clearInstallCache()
            await connector.clearFailure()
            guard let self else { return }
            self.step = .detecting
            self.restartPolling()
        }
    }

    /// Tap on the recovery button when in `.failed` state.
    func tappedRecovery() {
        // Clear-failure must complete before polling resumes — otherwise the very
        // first `currentStep()` call sees stale `failedState` and bounces back to
        // `.failed` before the connector can re-detect.
        Task { [connector, weak self] in
            await connector.clearFailure()
            guard let self else { return }
            self.step = .detecting
            self.restartPolling()
        }
    }

    /// Cancel any in-flight polling task and start a fresh one. Used by both
    /// recovery paths because `start()`'s "skip if pollingTask != nil" guard
    /// would otherwise keep us locked to a Task that already returned on
    /// `.failed` — leaving the UI showing `.detecting` with no live polling
    /// loop to drive the state machine forward.
    private func restartPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        start()
    }

    /// Connected — user wants to add another provider.
    func tappedAddAnother() {
        onOutcome(.addAnother)
    }

    /// Connected — user wants to finish.
    func tappedAllSet() {
        onOutcome(.allSet)
    }

    /// Debug-only: force the connector to its connected state so beta/debug
    /// builds can click through every onboarding screen and the synthesis queue
    /// without real auth or an installed extension. Stops polling so the forced
    /// state isn't reverted on the next tick. Gated in the UI by `BuildInfo.showsDebugTools`.
    func debugForceConnect() {
        stop()
        step = .connected(plan: "Demo")
    }

    // MARK: - Polling

    private func runPollingLoop() async {
        var stateEnteredAt = Date()
        var lastStep: ConnectorStep = .detecting

        while !Task.isCancelled {
            let current = await connector.currentStep()
            await MainActor.run { self.step = current }

            // Terminal states — stop polling.
            if case .connected = current { return }
            if case .failed = current { return }
            if case .skipped = current {
                // Propagate skip immediately — don't wait for a user tap.
                await MainActor.run { self.onOutcome(.skipped) }
                return
            }

            // Reset the clock whenever the state changes so slow user-driven
            // flows (OAuth in browser, reading docs) don't fire a spurious timeout.
            if current != lastStep {
                lastStep = current
                stateEnteredAt = Date()
            }

            // Stuck-detection: if the step hasn't changed in the per-state threshold
            // and we're in a waiting state, surface a timeout so the user has an
            // actionable next step.
            if Date().timeIntervalSince(stateEnteredAt) > stuckThreshold(for: current),
               isWaitingState(current) {
                await MainActor.run { self.step = .failed(.detectionTimeout) }
                return
            }

            try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
    }

    /// Per-state stuck threshold.
    /// User-driven auth states get 10 minutes because the user is in their browser.
    /// Install/detection states get 3 minutes — they should complete automatically.
    private nonisolated func stuckThreshold(for step: ConnectorStep) -> TimeInterval {
        switch step {
        case .awaitingOAuth, .awaitingExternalAuth, .awaitingUserConfirm:
            return 600  // 10 min — user is in their browser
        default:
            return 180  // 3 min — install/detection should be much faster
        }
    }

    private nonisolated func isWaitingState(_ step: ConnectorStep) -> Bool {
        switch step {
        case .waitingForExternalApp, .installing, .installingDependency,
             .awaitingOAuth, .awaitingUserConfirm, .confirmingInstall,
             .awaitingExternalAuth, .openProviderSite, .pasteAPIKey:
            return true
        default:
            return false
        }
    }
}
