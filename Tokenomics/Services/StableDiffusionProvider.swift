import Foundation
import os

/// Stability AI usage provider — tracks prepaid credit balance with purchase detection.
///
/// Auth: API key stored in Keychain via APIKeyService.
///
/// Unlike monthly-quota providers, Stability AI uses prepaid credits with no automatic reset.
/// This provider detects purchases (balance increases) and tracks usage against the balance
/// at last purchase to calculate utilization.
///
/// Local history is stored in UserDefaults to support 7-day run rate estimation.
///
/// API: `GET https://api.stability.ai/v1/user/balance`
/// Response: `{ "credits": 4.523 }`
actor StableDiffusionProvider: UsageProvider {
    let id = ProviderId.stableDiffusion
    let pollInterval: TimeInterval = 600 // 10 min — balance changes slowly

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "StableDiffusionProvider")

    func checkConnection() async -> ProviderConnectionState {
        guard let apiKey = APIKeyService.read(for: .stableDiffusion) else {
            return .notInstalled // No API key = not connected
        }
        do {
            let balance = try await fetchBalance(apiKey: apiKey)
            return .connected(plan: String(format: "%.1f credits", balance))
        } catch {
            Self.log.warning("Stable Diffusion connection check failed: \(error.localizedDescription)")
            return .installedNoAuth
        }
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        guard let apiKey = APIKeyService.read(for: .stableDiffusion) else {
            throw AppError.notAuthenticated
        }
        let currentBalance = try await fetchBalance(apiKey: apiKey)

        // Update local history
        var history = BalanceHistory.load()

        // Detect purchase: balance went up meaningfully
        if currentBalance > (history.lastKnownBalance ?? 0) + 0.01 {
            history.cycleStartBalance = currentBalance
            history.cycleStartDate = Date()
        }

        // First run: seed cycle start with current balance
        if history.cycleStartBalance == nil {
            history.cycleStartBalance = currentBalance
            history.cycleStartDate = Date()
        }

        // Record daily snapshot for run rate calculation
        history.recordSnapshot(balance: currentBalance)
        history.lastKnownBalance = currentBalance
        history.save()

        return mapToSnapshot(currentBalance: currentBalance, history: history)
    }

    // MARK: - API

    private func fetchBalance(apiKey: String) async throws -> Double {
        var request = URLRequest(url: URL(string: "https://api.stability.ai/v1/user/balance")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let balanceResponse = try JSONDecoder().decode(StabilityBalanceResponse.self, from: data)
        return balanceResponse.credits
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401: throw AppError.tokenExpired
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            throw AppError.rateLimited(retryAfter: retryAfter)
        default:
            throw AppError.httpError(statusCode: http.statusCode)
        }
    }

    // MARK: - Mapping

    private func mapToSnapshot(currentBalance: Double, history: BalanceHistory) -> ProviderUsageSnapshot {
        let cycleStart = history.cycleStartBalance ?? currentBalance
        let used = max(cycleStart - currentBalance, 0)
        let utilization = cycleStart > 0 ? (used / cycleStart) * 100 : 0

        let dailyRate = history.averageDailyUsage(days: 7)
        let sublabel: String
        if dailyRate > 0.01 {
            let daysRemaining = Int(currentBalance / dailyRate)
            sublabel = String(format: "%.1f remaining · ~%dd at current pace", currentBalance, daysRemaining)
        } else {
            sublabel = String(format: "%.1f credits remaining", currentBalance)
        }

        // Estimated depletion date based on 7-day run rate
        let estimatedDepletion: Date
        if dailyRate > 0.01 {
            estimatedDepletion = Date().addingTimeInterval(currentBalance / dailyRate * 86400)
        } else {
            estimatedDepletion = Date.distantFuture
        }

        let cycleStartDate = history.cycleStartDate ?? Date()
        let cycleDuration = max(estimatedDepletion.timeIntervalSince(cycleStartDate), 86400)

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Credits",
                utilization: min(utilization, 999),
                resetsAt: estimatedDepletion,
                windowDuration: cycleDuration,
                sublabelOverride: sublabel
            ),
            longWindow: nil,
            planLabel: String(format: "%.0f credits", cycleStart),
            extraUsage: nil,
            creditsBalance: String(format: "%.1f", currentBalance)
        )
    }
}

// MARK: - Response Model

private struct StabilityBalanceResponse: Decodable {
    let credits: Double
}

// MARK: - Local Balance History

/// Persists balance history locally for purchase detection and run rate calculation.
/// Stored in UserDefaults — small data, no network dependency.
private struct BalanceHistory: Codable {
    var cycleStartBalance: Double?
    var cycleStartDate: Date?
    var lastKnownBalance: Double?
    /// Rolling daily snapshots — keep last 30 days
    var dailySnapshots: [DailySnapshot] = []

    struct DailySnapshot: Codable {
        let date: Date
        let balance: Double
    }

    mutating func recordSnapshot(balance: Double) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let last = dailySnapshots.last,
           calendar.isDate(last.date, inSameDayAs: today) {
            // Update today's entry with the latest balance
            dailySnapshots[dailySnapshots.count - 1] = DailySnapshot(date: today, balance: balance)
        } else {
            dailySnapshots.append(DailySnapshot(date: today, balance: balance))
        }

        // Prune to last 30 days
        let cutoff = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        dailySnapshots = dailySnapshots.filter { $0.date >= cutoff }
    }

    /// Average daily credit consumption over the last N days.
    /// Returns 0 if insufficient history exists.
    func averageDailyUsage(days: Int) -> Double {
        guard dailySnapshots.count >= 2 else { return 0 }

        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let relevant = dailySnapshots.filter { $0.date >= cutoff }

        guard let oldest = relevant.first,
              let newest = relevant.last,
              oldest.date != newest.date else { return 0 }

        let totalUsed = oldest.balance - newest.balance
        guard totalUsed > 0 else { return 0 }

        let daysBetween = max(
            calendar.dateComponents([.day], from: oldest.date, to: newest.date).day ?? 1,
            1
        )
        return totalUsed / Double(daysBetween)
    }

    // MARK: - Persistence

    private static let key = "stableDiffusion_balanceHistory"

    static func load() -> BalanceHistory {
        guard let data = UserDefaults.standard.data(forKey: key),
              let history = try? JSONDecoder().decode(BalanceHistory.self, from: data) else {
            return BalanceHistory()
        }
        return history
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
