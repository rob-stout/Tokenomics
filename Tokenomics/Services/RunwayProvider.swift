import Foundation
import os

/// Runway usage provider — tracks prepaid credit balance via the credits API.
///
/// Auth: API key stored in Keychain via APIKeyService.
///
/// API: `GET https://api.dev.runwayml.com/v1/credits`
/// Requires `X-Runway-Version` header — without it the API returns HTTP 400
/// regardless of key validity.
/// Response: `{ "balance": { "used": Int, "total": Int, "resetsAt": "ISO8601"? } }`
actor RunwayProvider: UsageProvider {
    let id = ProviderId.runway
    let pollInterval: TimeInterval = 300 // 5 min

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "RunwayProvider")

    func checkConnection() async -> ProviderConnectionState {
        guard let apiKey = APIKeyService.read(for: .runway) else {
            return .notInstalled // No API key = not connected
        }
        do {
            _ = try await fetchCredits(apiKey: apiKey)
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
        let usage = try await fetchCredits(apiKey: apiKey)
        return mapToSnapshot(usage)
    }

    // MARK: - API

    private func fetchCredits(apiKey: String) async throws -> RunwayCreditsResponse {
        var request = URLRequest(url: URL(string: "https://api.dev.runwayml.com/v1/credits")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Required by Runway — omitting this header returns HTTP 400 regardless of key validity
        request.setValue("2024-11-06", forHTTPHeaderField: "X-Runway-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        do {
            return try JSONDecoder().decode(RunwayCreditsResponse.self, from: data)
        } catch {
            Self.log.error("Runway decode failed: \(error). Body: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            throw AppError.decodingFailed(underlying: error)
        }
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

    private func mapToSnapshot(_ response: RunwayCreditsResponse) -> ProviderUsageSnapshot {
        let used = response.credits.used
        let total = response.credits.total
        let utilization = total > 0 ? Double(used) / Double(total) * 100 : 0

        let resetsAt: Date
        if let resetStr = response.credits.resetsAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            resetsAt = formatter.date(from: resetStr) ?? Date.distantFuture
        } else {
            resetsAt = Date.distantFuture
        }

        let cycleStart = Date()
        let cycleDuration = max(resetsAt.timeIntervalSince(cycleStart), 30 * 24 * 3600)

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Credits",
                utilization: min(utilization, 999),
                resetsAt: resetsAt,
                windowDuration: cycleDuration,
                sublabelOverride: "\(used) / \(total) used"
            ),
            longWindow: nil,
            planLabel: "API",
            extraUsage: nil,
            creditsBalance: nil
        )
    }
}

// MARK: - Response Model

private struct RunwayCreditsResponse: Decodable {
    let credits: Credits

    struct Credits: Decodable {
        let used: Int
        let total: Int
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case used, total
            case resetsAt = "resets_at"
        }
    }
}
