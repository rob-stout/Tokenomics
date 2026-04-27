import SwiftUI
import os

/// Drives one provider's connector flow. Owns the polling timer that re-checks
/// the connector's state machine, marshals state from the provider's actor back
/// to the main actor for SwiftUI, and manages post-connection chaining
/// (Add another provider / I'm all set).
@MainActor
final class ConnectorViewModel: ObservableObject {

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ConnectorViewModel")

    // MARK: - Published state

    @Published private(set) var step: ConnectorStep = .detecting

    /// Display name shown in the connector header.
    let providerName: String

    let providerId: ProviderId

    let mode: ConnectorMode

    // MARK: - Outcome

    /// Emitted when the user chooses what to do after connecting.
    enum Outcome {
        /// User wants to connect another provider next.
        case addAnother
        /// User is done with onboarding.
        case allSet
    }

    private let onOutcome: (Outcome) -> Void

    // MARK: - Internal

    private let connector: any ProviderConnector
    private var pollingTask: Task<Void, Never>?

    /// Polling cadence while detection / install / OAuth is in progress.
    private static let pollInterval: TimeInterval = 1.5

    /// Hard ceiling on how long we'll wait without any state change before
    /// surfacing a `.detectionTimeout` error.
    private static let stuckThreshold: TimeInterval = 90

    // MARK: - Init

    init(connector: any ProviderConnector,
         onOutcome: @escaping (Outcome) -> Void) {
        self.connector = connector
        self.providerId = connector.id
        self.providerName = connector.id.displayName
        self.mode = connector.mode
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

    /// Tap on the recovery button when in `.failed` state.
    func tappedRecovery() {
        // Kick the polling loop back into life with a fresh detection.
        step = .detecting
        if pollingTask == nil { start() }
    }

    /// Connected — user wants to add another provider.
    func tappedAddAnother() {
        onOutcome(.addAnother)
    }

    /// Connected — user wants to finish.
    func tappedAllSet() {
        onOutcome(.allSet)
    }

    // MARK: - Polling

    private func runPollingLoop() async {
        let started = Date()
        var lastStep: ConnectorStep = .detecting

        while !Task.isCancelled {
            let current = await connector.currentStep()
            await MainActor.run { self.step = current }

            // Terminal states — stop polling.
            if case .connected = current { return }
            if case .failed = current { return }

            // Stuck-detection: if the step hasn't changed in `stuckThreshold` and
            // we're in a waiting state, surface a timeout so the user has an
            // actionable next step.
            if current == lastStep,
               Date().timeIntervalSince(started) > Self.stuckThreshold,
               isWaitingState(current) {
                await MainActor.run { self.step = .failed(.detectionTimeout) }
                return
            }
            lastStep = current

            try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
    }

    private nonisolated func isWaitingState(_ step: ConnectorStep) -> Bool {
        switch step {
        case .waitingForExternalApp, .installing, .awaitingOAuth: return true
        default: return false
        }
    }
}
