import Foundation
import os

/// Runway usage provider — tracks the prepaid API credit balance.
///
/// Auth: API key stored in Keychain via APIKeyService.
///
/// API: `GET https://api.dev.runwayml.com/v1/organization` (per Runway's OpenAPI
/// spec). Requires the `X-Runway-Version: 2024-11-06` header.
/// Response: `{ "tier": {...}, "creditBalance": Int, "usage": {...} }`
///
/// API credits are prepaid with no monthly reset, so — like Stability — this
/// detects top-ups (balance increases) and measures usage since the last one,
/// with a run-out estimate from the 7-day pace. There is no fake reset date.
actor RunwayProvider: UsageProvider {
    let id = ProviderId.runway
    let pollInterval: TimeInterval = 600 // 10 min — balance changes slowly

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "RunwayProvider")
    private static let historyKey = "runway_balanceHistory"

    func checkConnection() async -> ProviderConnectionState {
        if let forced = DetectionScenario.current.forcedConnection { return forced }
        guard let apiKey = APIKeyService.read(for: .runway) else {
            return .notInstalled // No API key = not connected
        }
        do {
            _ = try await fetchOrganization(apiKey: apiKey)
            return .connected(plan: "API")
        } catch {
            Self.log.warning("Runway connection check failed: \(error.localizedDescription)")
            return .installedNoAuth
        }
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        guard let apiKey = APIKeyService.read(for: .runway) else {
            throw AppError.notAuthenticated
        }
        let org = try await fetchOrganization(apiKey: apiKey)
        let balance = Double(org.creditBalance)

        var history = BalanceHistory.load(key: Self.historyKey)
        Self.recordBalance(balance, in: &history)
        history.save(key: Self.historyKey)

        return Self.mapToSnapshot(currentBalance: balance, history: history)
    }

    // MARK: - API

    private func fetchOrganization(apiKey: String) async throws -> RunwayOrganizationResponse {
        var request = URLRequest(url: URL(string: "https://api.dev.runwayml.com/v1/organization")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Required by Runway — omitting this header returns HTTP 400 regardless of key validity
        request.setValue("2024-11-06", forHTTPHeaderField: "X-Runway-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        do {
            return try Self.decodeOrganization(data)
        } catch {
            Self.log.error("Runway decode failed: \(error)")
            throw AppError.decodingFailed(underlying: error)
        }
    }

    nonisolated static func decodeOrganization(_ data: Data) throws -> RunwayOrganizationResponse {
        try JSONDecoder().decode(RunwayOrganizationResponse.self, from: data)
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

    // MARK: - Balance history

    /// Same top-up detection as Stability: a rising balance starts a new cycle.
    nonisolated static func recordBalance(_ balance: Double, in history: inout BalanceHistory, now: Date = Date()) {
        if balance > (history.lastKnownBalance ?? 0) + 0.01 || history.cycleStartBalance == nil {
            history.cycleStartBalance = balance
            history.cycleStartDate = now
        }
        history.recordSnapshot(balance: balance)
        history.lastKnownBalance = balance
    }

    // MARK: - Mapping

    nonisolated static func mapToSnapshot(
        currentBalance: Double,
        history: BalanceHistory,
        now: Date = Date()
    ) -> ProviderUsageSnapshot {
        let cycleStart = history.cycleStartBalance ?? currentBalance
        let used = max(cycleStart - currentBalance, 0)
        let utilization = cycleStart > 0 ? (used / cycleStart) * 100 : 0

        let dailyRate = history.averageDailyUsage(days: 7)
        let balanceText = Int(currentBalance.rounded()).formatted()
        let sublabel: String
        let estimatedDepletion: Date
        if dailyRate > 0.01 {
            let daysRemaining = Int(currentBalance / dailyRate)
            sublabel = "\(balanceText) remaining \u{00B7} ~\(daysRemaining)d at current pace"
            estimatedDepletion = now.addingTimeInterval(currentBalance / dailyRate * 86400)
        } else {
            sublabel = "\(balanceText) credits remaining"
            estimatedDepletion = Date.distantFuture
        }

        let cycleStartDate = history.cycleStartDate ?? now
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
            planLabel: "API",
            extraUsage: nil,
            creditsBalance: balanceText
        )
    }
}

// MARK: - Response Model

/// Only the field we use is decoded; `tier` and `usage` are ignored so spec
/// additions never break decoding.
struct RunwayOrganizationResponse: Decodable {
    let creditBalance: Int
}
