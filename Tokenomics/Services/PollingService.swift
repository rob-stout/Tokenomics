import Foundation

/// Manages periodic polling with per-provider intervals and activity-aware sleep/wake.
///
/// Ticks every 60s. On each tick, checks which providers are due for a fetch
/// based on their individual `pollInterval`. Local providers (Codex, Gemini)
/// poll every minute; remote providers (Claude) poll less frequently.
///
/// When idle (no activity for `idleTimeout`): stops polling to save resources.
/// When activity resumes: immediately fetches and restarts.
actor PollingService {
    private var task: Task<Void, Never>?
    private let tickInterval: TimeInterval = 60 // Check every minute
    private let idleTimeout: TimeInterval
    private var lastActivity: Date = Date()
    private var storedAction: (@Sendable (ProviderId) async -> Void)?
    private var providerSchedules: [ProviderId: ProviderSchedule] = [:]

    struct ProviderSchedule {
        let interval: TimeInterval
        var lastFetched: Date?

        func isDue(now: Date) -> Bool {
            guard let last = lastFetched else { return true }
            return now.timeIntervalSince(last) >= interval
        }
    }

    init(idleTimeout: TimeInterval = 540) { // 9 min idle
        self.idleTimeout = idleTimeout
    }

    var isRunning: Bool { task != nil }

    /// Register a provider's poll interval
    func registerProvider(_ id: ProviderId, interval: TimeInterval) {
        providerSchedules[id] = ProviderSchedule(interval: interval, lastFetched: nil)
    }

    /// Record external activity (e.g. filesystem change in ~/.claude).
    /// Wakes polling if it was sleeping.
    func noteActivity() {
        let wasIdle = isIdle
        lastActivity = Date()

        if wasIdle, task == nil, let action = storedAction {
            startLoop(action: action)
        }
    }

    /// Whether enough time has passed since last activity to consider idle.
    var isIdle: Bool {
        Date().timeIntervalSince(lastActivity) > idleTimeout
    }

    /// Starts polling, calling the provided closure with each provider ID when it's due.
    /// No-op if polling is already active.
    func start(action: @escaping @Sendable (ProviderId) async -> Void) {
        storedAction = action
        guard task == nil else { return }
        lastActivity = Date()
        startLoop(action: action)
    }

    func stop() {
        task?.cancel()
        task = nil
        storedAction = nil
    }

    /// Mark a provider as just-fetched (called after manual refresh)
    func markFetched(_ id: ProviderId) {
        providerSchedules[id]?.lastFetched = Date()
    }

    // MARK: - Private

    private func startLoop(action: @escaping @Sendable (ProviderId) async -> Void) {
        task = Task {
            // Fetch all providers immediately on start/wake
            let now = Date()
            for id in providerSchedules.keys {
                providerSchedules[id]?.lastFetched = now
                await action(id)
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(tickInterval))
                guard !Task.isCancelled else { break }

                if isIdle {
                    break
                }

                // Check which providers are due
                let now = Date()
                for (id, schedule) in providerSchedules where schedule.isDue(now: now) {
                    providerSchedules[id]?.lastFetched = now
                    await action(id)
                }
            }

            // If we exited due to idle (not cancellation), nil out task
            // so noteActivity() can restart us
            if !Task.isCancelled {
                task = nil
            }
        }
    }
}
