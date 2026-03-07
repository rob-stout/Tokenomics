import Foundation
import os

/// Fetches usage data from the Anthropic API
actor UsageService {
    // Compile-time constant — URL(string:) only fails on malformed strings
    private let baseURL = URL(string: "https://api.anthropic.com/api/oauth/usage")! // swiftlint:disable:this force_unwrapping

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "UsageService")

    /// Earliest time we're allowed to retry after a 429
    private var rateLimitedUntil: Date?

    /// Consecutive 429 count for exponential backoff (resets on success)
    private var consecutive429s: Int = 0

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // API returns fractional seconds (e.g. "2026-02-25T20:00:00.849139+00:00")
        // which the default .iso8601 strategy can't parse
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) {
                return date
            }
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(string)")
        }
        return decoder
    }()

    func fetchUsage(token: String) async throws -> UsageData {
        // Respect rate-limit backoff — don't hit the API if we're still in a cooldown
        if let until = rateLimitedUntil, Date() < until {
            let remaining = until.timeIntervalSinceNow
            Self.log.info("Skipping fetch — rate-limited for \(Int(remaining))s more")
            throw AppError.rateLimited(retryAfter: remaining)
        }

        var request = URLRequest(url: baseURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            rateLimitedUntil = nil
            consecutive429s = 0
            Self.log.info("Usage fetch succeeded")
        case 401, 403:
            throw AppError.tokenExpired
        case 429:
            consecutive429s += 1
            // Exponential backoff: 5 min → 10 min → 20 min → 40 min (capped at 1 hour)
            let baseBackoff: TimeInterval = 300
            let backoff = min(baseBackoff * pow(2, Double(consecutive429s - 1)), 3600)
            rateLimitedUntil = Date().addingTimeInterval(backoff)
            let body = String(data: data, encoding: .utf8) ?? ""
            Self.log.warning("429 Rate Limited (#\(self.consecutive429s)) — backing off \(Int(backoff))s. Body: \(body, privacy: .public)")
            throw AppError.rateLimited(retryAfter: backoff)
        default:
            throw AppError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(UsageData.self, from: data)
        } catch {
            if let raw = String(data: data, encoding: .utf8) {
                print("[UsageService] Raw API response: \(raw)")
            }
            print("[UsageService] Decode error: \(error)")
            throw AppError.decodingFailed(underlying: error)
        }
    }
}
