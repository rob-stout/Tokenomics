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
