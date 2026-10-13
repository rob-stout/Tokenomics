import Foundation

enum AppError: Error, LocalizedError {
    case notAuthenticated
    case tokenExpired
    /// Claude's keychain item exists but the user hasn't allowed Tokenomics to read it.
    case keychainAccessNeeded
    case rateLimited(retryAfter: TimeInterval?)
    case networkUnavailable
    case decodingFailed(underlying: Error)
    case httpError(statusCode: Int)
    case unexpectedError(underlying: Error)

    /// True only for the token-expired case, used to tailor recovery UI.
    var isTokenExpired: Bool {
        if case .tokenExpired = self { return true }
        return false
    }

    var needsKeychainAccess: Bool {
        if case .keychainAccessNeeded = self { return true }
        return false
    }

    /// True when the API returned 429
    var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in"
        case .tokenExpired:
            return "Session expired — re-authenticate in your terminal, then click Refresh."
        case .keychainAccessNeeded:
            return "Keychain access needed — click Allow Access to let Tokenomics read Claude Code's sign-in."
        case .rateLimited:
            return "Couldn't load usage data — check back in a few minutes"
        case .networkUnavailable:
            return "No network connection"
        case .decodingFailed:
            return "Couldn't read usage data"
        case .httpError(let code):
            return "Server error (\(code))"
        case .unexpectedError:
            return "Something went wrong — try again"
        }
    }
}
