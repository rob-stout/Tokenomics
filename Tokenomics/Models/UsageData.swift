import Foundation

/// Maps directly to the API response from /api/oauth/usage
struct UsageData: Decodable, Sendable {
    let fiveHour: UsagePeriod
    let sevenDay: UsagePeriod
    let sevenDayOauthApps: UsagePeriod?
    let sevenDayOpus: UsagePeriod?
    let sevenDaySonnet: UsagePeriod?
    let sevenDayCowork: UsagePeriod?
    let extraUsage: ExtraUsage?

    /// Inferred plan type based on available usage data
    var inferredPlan: PlanType {
        if extraUsage?.isEnabled == true {
            return .max
        } else if sevenDayOpus != nil || sevenDaySonnet != nil {
            return .pro
        } else {
            return .free
        }
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extra_usage"
    }
}

struct UsagePeriod: Decodable, Sendable {
    let utilization: Double
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// Formatted time remaining until reset
    var timeUntilReset: String {
        let interval = resetsAt.timeIntervalSinceNow
        guard interval > 0 else { return "Resetting now" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours >= 24 {
            let calendar = Calendar.current
            if calendar.isDateInToday(resetsAt) {
                return "Resets today"
            } else if calendar.isDateInTomorrow(resetsAt) {
                return "Resets tomorrow"
            } else {
                return "Resets \(Self.dayFormatter.string(from: resetsAt))"
            }
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
}

struct ExtraUsage: Decodable, Sendable {
    let isEnabled: Bool
    let monthlyLimit: Int?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }

    /// Monthly limit formatted as dollars (API uses cents)
    var monthlyLimitFormatted: String {
        guard let monthlyLimit else { return "$0.00" }
        return String(format: "$%.2f", Double(monthlyLimit) / 100.0)
    }

    /// Used credits formatted as dollars
    var usedCreditsFormatted: String {
        guard let usedCredits else { return "$0.00" }
        return String(format: "$%.2f", usedCredits / 100.0)
    }
}

/// User's Claude plan, inferred from API response shape
enum PlanType: String {
    case free = "Free"
    case pro = "Pro"
    case max = "Max"
}

/// Represents the visual state of usage for icon/color decisions
enum UsageState {
    case healthy
    case caution
    case warning
    case depleted
    case error
    case loading
    case unauthenticated

    init(utilization: Double) {
        switch utilization {
        case 0..<70: self = .healthy
        case 70..<90: self = .caution
        case 90..<100: self = .warning
        default: self = .depleted
        }
    }
}
