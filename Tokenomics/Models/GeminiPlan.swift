import Foundation

/// Gemini CLI plan tiers with their documented rate limits
enum GeminiPlan: String, CaseIterable, Codable, Sendable {
    case free
    case standard
    case enterprise

    var displayLabel: String {
        switch self {
        case .free: return "Free (ended)"
        case .standard: return "Standard"
        case .enterprise: return "Enterprise"
        }
    }

    /// Longer label for the plan picker. The raw values stay as-is so saved
    /// settings still decode; `.free` is kept for existing users but relabelled
    /// honestly since Google stopped serving personal accounts on 2026-06-18.
    var pickerLabel: String {
        switch self {
        case .free: return "Free (personal accounts \u{2014} ended June 2026)"
        case .standard: return "Code Assist Standard"
        case .enterprise: return "Code Assist Enterprise"
        }
    }

    /// Shown wherever the user connects or picks a Gemini CLI plan.
    static let personalAccountNotice =
        "Tokenomics tracks Gemini CLI when it's signed in with a Gemini Code Assist Standard or Enterprise license. Personal Google accounts no longer work with Gemini CLI (they moved to Antigravity CLI in June 2026)."

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

/// Consumer Gemini (gemini.google.com app) subscription tiers, post-2025 rename.
/// Label-only: the app pool's usage % comes directly from the web response, so —
/// unlike `GeminiPlan` for the CLI — this drives no limit calculation. It exists
/// only to name the plan badge, since the extension can't read the tier reliably.
enum GeminiConsumerPlan: String, CaseIterable, Codable, Sendable {
    case free
    case plus
    case pro
    case ultra

    var displayLabel: String {
        switch self {
        case .free:  return "Free"
        case .plus:  return "AI Plus"
        case .pro:   return "AI Pro"
        case .ultra: return "AI Ultra"
        }
    }

    /// One-line description shown under the picker.
    var blurb: String {
        switch self {
        case .free:  return "gemini.google.com, no subscription"
        case .plus:  return "Google AI Plus"
        case .pro:   return "Google AI Pro (formerly Gemini Advanced)"
        case .ultra: return "Google AI Ultra"
        }
    }
}
