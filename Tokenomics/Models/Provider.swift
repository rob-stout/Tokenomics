import Foundation

// MARK: - Provider Identity

/// Supported AI coding tool providers
enum ProviderId: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        case .gemini: return "Gemini CLI"
        }
    }

    /// Single-letter label for menu bar and tab icons
    var shortLabel: String {
        switch self {
        case .claude: return "C"
        case .codex: return "X"
        case .gemini: return "G"
        }
    }

    /// Terminal command to authenticate
    var loginCommand: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex login"
        case .gemini: return "gemini login"
        }
    }

    /// Install instructions URL
    var installURL: URL? {
        switch self {
        case .claude: return URL(string: "https://code.claude.com/docs/en/setup")
        case .codex: return URL(string: "https://github.com/openai/codex")
        case .gemini: return URL(string: "https://github.com/google-gemini/gemini-cli")
        }
    }
}

// MARK: - Connection State

/// Describes the current state of a provider's connection
enum ProviderConnectionState: Sendable, Equatable {
    case notInstalled
    case installedNoAuth
    case connected(plan: String)
    case authExpired
    case unavailable(reason: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .installedNoAuth: return "Not signed in"
        case .connected(let plan): return "\(plan) — Connected"
        case .authExpired: return "Auth expired"
        case .unavailable(let reason): return reason
        }
    }
}

// MARK: - Usage Snapshot

/// Provider-agnostic usage data that the UI renders
struct ProviderUsageSnapshot: Sendable {
    let shortWindow: WindowUsage
    let longWindow: WindowUsage
    let planLabel: String
    let extraUsage: ExtraUsage?
    let creditsBalance: String?
}

/// A single usage window (e.g. 5-hour or 7-day)
struct WindowUsage: Sendable {
    let label: String
    let utilization: Double
    let resetsAt: Date
    let windowDuration: TimeInterval

    /// Pace: how far through the window we are (0–1)
    var pace: Double {
        let remaining = max(resetsAt.timeIntervalSinceNow, 0)
        let elapsed = windowDuration - min(remaining, windowDuration)
        return min(max(elapsed / windowDuration, 0), 1)
    }

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
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return "Resets \(formatter.string(from: resetsAt))"
            }
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
}

// MARK: - Per-Provider State (Published by ViewModel)

/// Everything the UI needs to render one provider's panel
struct ProviderState: Sendable {
    let connection: ProviderConnectionState
    let usage: ProviderUsageSnapshot?
    let error: AppError?
    let lastSynced: Date?
    let isLoading: Bool

    static let empty = ProviderState(
        connection: .notInstalled,
        usage: nil,
        error: nil,
        lastSynced: nil,
        isLoading: false
    )
}

// MARK: - Provider Protocol

/// Abstraction for any AI coding tool usage provider
protocol UsageProvider: Actor {
    var id: ProviderId { get }

    /// Check whether the CLI is installed and authenticated
    func checkConnection() async -> ProviderConnectionState

    /// Fetch the latest usage data. Throws on failure.
    func fetchUsage() async throws -> ProviderUsageSnapshot
}
