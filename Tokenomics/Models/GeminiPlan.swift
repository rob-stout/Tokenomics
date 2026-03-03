import Foundation

/// Gemini CLI plan tiers with their documented rate limits
enum GeminiPlan: String, CaseIterable, Codable, Sendable {
    case free
    case standard
    case enterprise

    var displayLabel: String {
        switch self {
        case .free: return "Free"
        case .standard: return "Standard"
        case .enterprise: return "Enterprise"
        }
    }

    var dailyLimit: Int {
        switch self {
        case .free: return 1000
        case .standard: return 1500
        case .enterprise: return 2000
        }
    }

    var perMinuteLimit: Int {
        switch self {
        case .free: return 60
        case .standard, .enterprise: return 120
        }
    }

    /// Estimated daily token budget (Google enforces TPM, not TPD —
    /// these are practical estimates based on RPD × typical context size)
    var dailyTokenBudget: Int {
        switch self {
        case .free: return 2_000_000
        case .standard: return 3_000_000
        case .enterprise: return 4_000_000
        }
    }

    var limitSummary: String {
        let daily = dailyLimit.formatted()
        return "\(daily) requests/day \u{00B7} \(perMinuteLimit)/min"
    }
}
