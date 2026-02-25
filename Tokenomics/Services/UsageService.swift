import Foundation

/// Fetches usage data from the Anthropic API
actor UsageService {
    private let baseURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

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
        var request = URLRequest(url: baseURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw AppError.tokenExpired
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw AppError.rateLimited(retryAfter: retryAfter)
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
