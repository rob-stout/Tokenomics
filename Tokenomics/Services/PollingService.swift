import Foundation

/// Manages periodic polling for usage data
actor PollingService {
    private var task: Task<Void, Never>?
    private let interval: TimeInterval

    init(interval: TimeInterval = 300) { // 5 minutes default
        self.interval = interval
    }

    var isRunning: Bool { task != nil }

    /// Starts polling, calling the provided closure on each tick.
    /// No-op if polling is already active — prevents cancelling an in-flight
    /// fetch when the popover re-appears mid-cycle.
    func start(action: @escaping @Sendable () async -> Void) {
        guard task == nil else { return }
        task = Task {
            // Fetch immediately on start
            await action()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Force an immediate refresh outside the normal interval
    func refreshNow(action: @escaping @Sendable () async -> Void) {
        Task { await action() }
    }
}
