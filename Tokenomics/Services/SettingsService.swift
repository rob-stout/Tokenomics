import Foundation

/// Persists user preferences for multi-provider configuration
enum SettingsService {
    private static let defaults = UserDefaults.standard

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

}
