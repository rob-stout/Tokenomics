import SwiftUI
import Combine

/// Main view model connecting services to UI
@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var usageData: UsageData?
    @Published private(set) var error: AppError?
    @Published private(set) var isLoading = false
    @Published private(set) var lastSynced: Date?

    private let usageService = UsageService()
    private let pollingService = PollingService()

    // Cached token so we don't hit the Keychain on every poll tick or render pass.
    // Cleared when the API returns 401/403, forcing a fresh Keychain read.
    private var cachedToken: String? = nil

    var fiveHourUtilization: Double {
        usageData?.fiveHour.utilization ?? 0
    }

    var sevenDayUtilization: Double {
        usageData?.sevenDay.utilization ?? 0
    }

    /// How far through the 5-hour window we are (0–1).
    /// The pace dot sits here to show "ideal" even usage.
    var fiveHourPace: Double {
        guard let data = usageData else { return 0 }
        let totalWindow: TimeInterval = 5 * 3600
        let remaining = max(data.fiveHour.resetsAt.timeIntervalSinceNow, 0)
        let elapsed = totalWindow - remaining
        return min(max(elapsed / totalWindow, 0), 1)
    }

    /// How far through the 7-day window we are (0–1).
    var sevenDayPace: Double {
        guard let data = usageData else { return 0 }
        let totalWindow: TimeInterval = 7 * 24 * 3600
        let remaining = max(data.sevenDay.resetsAt.timeIntervalSinceNow, 0)
        let elapsed = totalWindow - remaining
        return min(max(elapsed / totalWindow, 0), 1)
    }

    var usageState: UsageState {
        guard cachedToken != nil else {
            return .unauthenticated
        }
        guard error == nil else { return .error }
        guard let data = usageData else { return .loading }
        return UsageState(utilization: data.fiveHour.utilization)
    }

    var planLabel: String {
        usageData?.inferredPlan.rawValue ?? "—"
    }

    var isAuthenticated: Bool {
        cachedToken != nil
    }

    func startPolling() {
        // Ensure we have a token before spinning up the poll loop.
        // If there's no token yet, bail — the LoginView will be shown.
        if cachedToken == nil {
            cachedToken = KeychainService.readAccessToken()
        }

        Task {
            await pollingService.start { [weak self] in
                await self?.fetchUsage()
            }
        }
    }

    func stopPolling() {
        Task {
            await pollingService.stop()
        }
    }

    func refresh() {
        Task {
            await fetchUsage()
            // If polling was stopped due to an expired token and the fetch
            // just succeeded (error is now nil), restart the loop so regular
            // background syncs resume without the user relaunching the app.
            let pollingStopped = await !pollingService.isRunning
            if pollingStopped && error == nil {
                await pollingService.start { [weak self] in
                    await self?.fetchUsage()
                }
            }
        }
    }

    // MARK: - Private

    private func fetchUsage() async {
        // Use the cached token. If it's gone, try the Keychain once more —
        // covers the case where the user signed in after the app launched.
        if cachedToken == nil {
            cachedToken = KeychainService.readAccessToken()
        }

        guard let token = cachedToken else {
            self.error = .notAuthenticated
            return
        }

        if usageData == nil {
            isLoading = true
        }

        do {
            let data = try await usageService.fetchUsage(token: token)
            self.usageData = data
            self.error = nil
            self.lastSynced = Date()
        } catch let appError as AppError {
            if case .tokenExpired = appError {
                // Cached token is invalid — discard it and halt the poll loop.
                // Hammering the API every 5 min with a dead token wastes quota
                // and could trigger rate-limiting. User must manually refresh
                // after re-authenticating via `claude` in the terminal.
                cachedToken = nil
                await pollingService.stop()
            }
            self.error = appError
        } catch {
            self.error = .networkUnavailable
        }

        isLoading = false
    }
}
