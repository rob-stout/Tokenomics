import Foundation

/// Persists user preferences for multi-provider configuration
enum SettingsService {
    // UserDefaults.standard is documented as thread-safe by Apple
    nonisolated(unsafe) private static let defaults = UserDefaults.standard

    // MARK: - Onboarding

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - Pinned Providers (Menu Bar Display)

    /// Providers pinned to show individual rings in the menu bar.
    /// Empty set = Smart mode (worst-of-N).
    static var pinnedProviders: Set<ProviderId> {
        get {
            guard let rawArray = defaults.stringArray(forKey: "pinnedProviders") else {
                return []
            }
            return Set(rawArray.compactMap { ProviderId(rawValue: $0) })
        }
        set {
            defaults.set(newValue.map(\.rawValue), forKey: "pinnedProviders")
        }
    }

    /// Toggle a provider's pin state
    static func togglePin(for provider: ProviderId) {
        var pins = pinnedProviders
        if pins.contains(provider) {
            pins.remove(provider)
        } else {
            pins.insert(provider)
        }
        pinnedProviders = pins
    }

    /// Whether Smart mode is active (no providers explicitly pinned)
    static var isSmartMode: Bool {
        pinnedProviders.isEmpty
    }

    // MARK: - Gemini Plan

    /// User-selected Gemini plan. nil = hasn't chosen yet (provider defaults to .free).
    static var geminiPlan: GeminiPlan? {
        get {
            defaults.string(forKey: "geminiPlan").flatMap { GeminiPlan(rawValue: $0) }
        }
        set {
            defaults.set(newValue?.rawValue, forKey: "geminiPlan")
        }
    }

    // MARK: - Copilot Plan Limit

    /// User-specified monthly premium request limit for Copilot.
    /// nil = use default (300 for Individual plan).
    static var copilotMonthlyLimit: Int? {
        get {
            let value = defaults.integer(forKey: "copilotMonthlyLimit")
            return value > 0 ? value : nil
        }
        set {
            if let limit = newValue {
                defaults.set(limit, forKey: "copilotMonthlyLimit")
            } else {
                defaults.removeObject(forKey: "copilotMonthlyLimit")
            }
        }
    }

    // MARK: - Provider Order & Visibility

    /// Custom provider order. Empty = default enum order.
    static var providerOrder: [ProviderId] {
        get {
            guard let rawArray = defaults.stringArray(forKey: "providerOrder") else {
                return []
            }
            return rawArray.compactMap { ProviderId(rawValue: $0) }
        }
        set {
            defaults.set(newValue.map(\.rawValue), forKey: "providerOrder")
        }
    }

    /// Providers hidden from the tab bar (still polled in background)
    static var hiddenProviders: Set<ProviderId> {
        get {
            guard let rawArray = defaults.stringArray(forKey: "hiddenProviders") else {
                return []
            }
            return Set(rawArray.compactMap { ProviderId(rawValue: $0) })
        }
        set {
            defaults.set(newValue.map(\.rawValue), forKey: "hiddenProviders")
        }
    }

    // MARK: - Selected Tab

    /// The last-selected provider tab (persisted across popover open/close)
    static var selectedTab: ProviderId? {
        get {
            defaults.string(forKey: "selectedTab").flatMap { ProviderId(rawValue: $0) }
        }
        set {
            defaults.set(newValue?.rawValue, forKey: "selectedTab")
        }
    }

    // MARK: - Notification Thresholds

    /// Per-provider notification configuration
    struct NotificationConfig: Codable {
        var isEnabled: Bool = true
        /// Percentage threshold at which to fire an alert (50–100, in 10% steps)
        var threshold: Int = 80
    }

    /// Which usage window(s) trigger alerts
    enum AlertWindow: String, Codable, CaseIterable {
        case short, long, both

        var displayLabel: String {
            switch self {
            case .short: return "Short"
            case .long: return "Long"
            case .both: return "Both"
            }
        }
    }

    /// Load per-provider notification config, returning the default if none saved
    static func notificationConfig(for provider: ProviderId) -> NotificationConfig {
        guard let data = defaults.data(forKey: "notificationConfig_\(provider.rawValue)"),
              let config = try? JSONDecoder().decode(NotificationConfig.self, from: data) else {
            return NotificationConfig()
        }
        return config
    }

    /// Persist per-provider notification config
    static func setNotificationConfig(_ config: NotificationConfig, for provider: ProviderId) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: "notificationConfig_\(provider.rawValue)")
    }

    /// Which usage window triggers alerts (default: short window only)
    static var alertWindow: AlertWindow {
        get {
            defaults.string(forKey: "alertWindow").flatMap { AlertWindow(rawValue: $0) } ?? .short
        }
        set {
            defaults.set(newValue.rawValue, forKey: "alertWindow")
        }
    }

    // MARK: - Usage Cache

    /// Save a provider's last successful usage snapshot to disk
    static func cacheUsage(_ snapshot: ProviderUsageSnapshot, for provider: ProviderId) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: "cachedUsage_\(provider.rawValue)")
        defaults.set(Date().timeIntervalSince1970, forKey: "cachedUsageTime_\(provider.rawValue)")
    }

    /// Load a provider's cached usage snapshot (if any)
    static func cachedUsage(for provider: ProviderId) -> (snapshot: ProviderUsageSnapshot, cachedAt: Date)? {
        guard let data = defaults.data(forKey: "cachedUsage_\(provider.rawValue)"),
              let snapshot = try? JSONDecoder().decode(ProviderUsageSnapshot.self, from: data) else {
            return nil
        }
        let timestamp = defaults.double(forKey: "cachedUsageTime_\(provider.rawValue)")
        let cachedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date.distantPast
        return (snapshot, cachedAt)
    }

}
