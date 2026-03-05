import Foundation

/// Manages periodic polling for usage data with activity-aware sleep/wake.
///
/// When active: polls at the configured interval (default 5 min).
/// When idle (no activity for `idleTimeout`): stops polling to avoid rate limits.
/// When activity resumes: immediately fetches and restarts the polling loop.
actor PollingService {
    private var task: Task<Void, Never>?
    private let interval: TimeInterval
    private let idleTimeout: TimeInterval
    private var lastActivity: Date = Date()
    private var storedAction: (@Sendable () async -> Void)?

    init(interval: TimeInterval = 300, idleTimeout: TimeInterval = 540) { // 5 min poll, 9 min idle
        self.interval = interval
        self.idleTimeout = idleTimeout
    }

    var isRunning: Bool { task != nil }

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

    /// Starts polling, calling the provided closure on each tick.
    /// No-op if polling is already active.
    func start(action: @escaping @Sendable () async -> Void) {
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

    // MARK: - Private

    private func startLoop(action: @escaping @Sendable () async -> Void) {
        task = Task {
            // Fetch immediately on start/wake
            await action()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }

                if isIdle {
                    // Go to sleep — ActivityMonitor will wake us via noteActivity()
                    break
                }

                await action()
            }

            // If we exited due to idle (not cancellation), nil out task
            // so noteActivity() can restart us
            if !Task.isCancelled {
                task = nil
            }
        }
    }
}
