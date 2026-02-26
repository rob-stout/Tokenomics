import Foundation

enum AppError: Error, LocalizedError {
    case notAuthenticated
    case tokenExpired
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

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in to Claude"
        case .tokenExpired:
            // Give the user a concrete next step, not just a status message.
            return "Session expired — run `claude` in your terminal to re-authenticate, then click Refresh."
        case .rateLimited:
            return "Too many requests — trying again shortly"
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
