import Foundation
import os

/// Refreshes expired Claude OAuth access tokens using the refresh token.
/// Mirrors the flow used by Claude Code and third-party tools.
actor TokenRefreshService {
    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "TokenRefresh")

    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let scopes = "user:profile user:inference user:sessions:claude_code user:mcp_servers"

    /// Buffer before expiry to proactively refresh (5 minutes)
    private static let refreshBuffer: TimeInterval = 300

    struct RefreshResult {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
    }

    /// Whether the token needs refreshing (expired or about to expire)
    static func needsRefresh(expiresAt: Date?) -> Bool {
        guard let expiresAt else { return false } // No expiry info — assume valid
        return Date() >= expiresAt.addingTimeInterval(-refreshBuffer)
    }

    /// Refresh an expired access token. Returns new tokens or throws.
    func refresh(using refreshToken: String) async throws -> RefreshResult {
        Self.log.info("Attempting token refresh")

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": Self.scopes
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenRefreshError.networkError
        }

        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            Self.log.error("Token refresh failed: invalid_grant or expired session")
            throw TokenRefreshError.sessionExpired
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            Self.log.error("Token refresh failed: HTTP \(httpResponse.statusCode)")
            throw TokenRefreshError.httpError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            throw TokenRefreshError.invalidResponse
        }

        let newRefreshToken = json["refresh_token"] as? String
        let expiresIn = (json["expires_in"] as? Double) ?? 3600

        Self.log.info("Token refreshed successfully, expires in \(Int(expiresIn))s")

        return RefreshResult(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken ?? refreshToken,
            expiresIn: expiresIn
        )
    }
}

enum TokenRefreshError: Error, LocalizedError {
    case sessionExpired
    case httpError(Int)
    case networkError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .sessionExpired: return "Session expired — re-authenticate with `claude` in Terminal"
        case .httpError(let code): return "Token refresh failed (HTTP \(code))"
        case .networkError: return "Network error during token refresh"
        case .invalidResponse: return "Invalid response from token refresh"
        }
    }
}
