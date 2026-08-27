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

    /// In-flight request shared across concurrent callers. Actors are reentrant
    /// across `await`, so without this a manual Refresh landing mid-poll (or an
    /// onboarding connection check colliding with a tick) fires a second
    /// simultaneous request — the exact burst pattern Anthropic's limiter 429s
    /// on with Retry-After: 0. Joiners await the same result instead.
    private var inFlight: Task<UsageData, Error>?

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

    /// Clear the rate limit state so a retry with a fresh token isn't blocked
    func resetRateLimit() {
        rateLimitedUntil = nil
        consecutive429s = 0
    }

    /// Backoff for a 429. Honors a positive server-sent Retry-After; falls back
    /// to exponential (5 min → 10 min → 20 min → 40 min, capped at 1 hour) when
    /// the header is absent or 0 — Anthropic sends Retry-After: 0 on momentary
    /// burst throttles, which is useless as a cooldown.
    static func backoffInterval(retryAfterHeader: TimeInterval?, consecutive429s: Int) -> TimeInterval {
        if let retryAfter = retryAfterHeader, retryAfter > 0 {
            return retryAfter
        }
        let baseBackoff: TimeInterval = 300
        return min(baseBackoff * pow(2, Double(consecutive429s - 1)), 3600)
    }

    func fetchUsage(token: String) async throws -> UsageData {
        // Join an in-flight request instead of firing a concurrent duplicate
        if let inFlight {
            return try await inFlight.value
        }

        // Respect rate-limit backoff — don't hit the API if we're still in a cooldown
        if let until = rateLimitedUntil, Date() < until {
            let remaining = until.timeIntervalSinceNow
            Self.log.info("Skipping fetch — rate-limited for \(Int(remaining))s more")
            throw AppError.rateLimited(retryAfter: remaining)
        }

        let task = Task { try await performFetch(token: token) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func performFetch(token: String) async throws -> UsageData {
        var request = URLRequest(url: baseURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.71", forHTTPHeaderField: "User-Agent")

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
            let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            let backoff = Self.backoffInterval(
                retryAfterHeader: retryAfterHeader,
                consecutive429s: consecutive429s
            )
            rateLimitedUntil = Date().addingTimeInterval(backoff)
            let body = String(data: data, encoding: .utf8) ?? ""
            Self.log.warning("429 Rate Limited (#\(self.consecutive429s)) — backing off \(Int(backoff))s. Body: \(body, privacy: .public)")
            throw AppError.rateLimited(retryAfter: backoff)
        default:
            throw AppError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            let usage = try decoder.decode(UsageData.self, from: data)
            Self.log.info("Plan inference: hasExtraUsage=\(usage.extraUsage != nil, privacy: .public), hasOpus=\(usage.sevenDayOpus != nil, privacy: .public), hasSonnet=\(usage.sevenDaySonnet != nil, privacy: .public) → \(usage.inferredPlan.rawValue, privacy: .public)")
            return usage
        } catch {
            if let raw = String(data: data, encoding: .utf8) {
                Self.log.error("Raw API response (decode failure): \(raw, privacy: .public)")
            }
            Self.log.error("Decode error: \(error.localizedDescription)")
            throw AppError.decodingFailed(underlying: error)
        }
    }
}
