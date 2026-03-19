import Foundation
import os

/// ElevenLabs usage provider — tracks monthly character quota via the subscription API.
///
/// Auth: API key stored in Keychain via APIKeyService.
///
/// API: `GET https://api.elevenlabs.io/v1/user/subscription`
/// Response includes character_count, character_limit, next_character_count_reset_unix, tier.
actor ElevenLabsProvider: UsageProvider {
    let id = ProviderId.elevenlabs
    let pollInterval: TimeInterval = 300 // 5 min

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ElevenLabsProvider")

    func checkConnection() async -> ProviderConnectionState {
        guard let apiKey = APIKeyService.read(for: .elevenlabs) else {
            return .notInstalled // No API key = not connected
        }
        do {
            let sub = try await fetchSubscription(apiKey: apiKey)
            return .connected(plan: sub.tierLabel)
        } catch {
            Self.log.warning("ElevenLabs connection check failed: \(error.localizedDescription)")
            return .installedNoAuth
        }
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        guard let apiKey = APIKeyService.read(for: .elevenlabs) else {
            throw AppError.notAuthenticated
        }
        let sub = try await fetchSubscription(apiKey: apiKey)
        return mapToSnapshot(sub)
    }

    // MARK: - API

    private func fetchSubscription(apiKey: String) async throws -> ElevenLabsSubscription {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        return try JSONDecoder().decode(ElevenLabsSubscription.self, from: data)
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

    private func mapToSnapshot(_ sub: ElevenLabsSubscription) -> ProviderUsageSnapshot {
        let used = sub.characterCount
        let limit = sub.characterLimit
        let utilization = limit > 0 ? Double(used) / Double(limit) * 100 : 0

        let resetsAt: Date
        if let resetUnix = sub.nextCharacterCountResetUnix {
            resetsAt = Date(timeIntervalSince1970: TimeInterval(resetUnix))
        } else {
            resetsAt = Date.distantFuture
        }

        // Estimate cycle as ~30 days from now to reset
        let cycleDuration: TimeInterval = 30 * 24 * 3600

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let usedStr = formatter.string(from: NSNumber(value: used)) ?? "\(used)"
        let limitStr = formatter.string(from: NSNumber(value: limit)) ?? "\(limit)"

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Characters",
                utilization: min(utilization, 999),
                resetsAt: resetsAt,
                windowDuration: cycleDuration,
                sublabelOverride: "\(usedStr) / \(limitStr) used"
            ),
            longWindow: nil,
            planLabel: sub.tierLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }
}

// MARK: - Response Model

private struct ElevenLabsSubscription: Decodable {
    let tier: String?
    let characterCount: Int
    let characterLimit: Int
    let nextCharacterCountResetUnix: Int?

    var tierLabel: String {
        guard let tier else { return "Free" }
        return tier.prefix(1).uppercased() + tier.dropFirst()
    }

    enum CodingKeys: String, CodingKey {
        case tier
        case characterCount = "character_count"
        case characterLimit = "character_limit"
        case nextCharacterCountResetUnix = "next_character_count_reset_unix"
    }
}
