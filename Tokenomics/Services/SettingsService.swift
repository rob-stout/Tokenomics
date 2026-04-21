import Foundation
import SwiftUI

/// User-selectable text size for the popover.
/// Maps to Apple's DynamicTypeSize ladder so semantic fonts scale correctly,
/// and exposes a matching icon scale + popover width so chrome that reads as
/// "text-adjacent" (provider icons, settings icons) grows with the type.
enum TextSize: String, CaseIterable, Codable {
    case compact
    case medium
    case large

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Multiplier for icons that should grow alongside text
    /// (provider tab icons, settings-row glyphs).
    /// Structural chrome (padding, progress bar height) does NOT use this.
    var iconScale: CGFloat {
        switch self {
        case .compact: return 1.0
        case .medium:  return 1.15
        case .large:   return 1.30
        }
    }

    /// The popover width for this text size, given how many provider tabs are visible.
    /// At 4+ providers the tab bar needs extra room for icon-only mode.
    func popoverWidth(providerCount: Int) -> CGFloat {
        let base: CGFloat = providerCount >= 4 ? 400 : 360
        switch self {
        case .compact: return base
        case .medium:  return base + 40   // 360→400, 400→440
        case .large:   return base + 90   // 360→450, 400→490
        }
    }
}

// MARK: - SwiftUI Environment

private struct TokenomicsTextSizeKey: EnvironmentKey {
    static let defaultValue: TextSize = .compact
}

extension EnvironmentValues {
    /// Current popover text size, propagated from PopoverView's root to all
    /// children that need to scale icons alongside text.
    var tokenomicsTextSize: TextSize {
        get { self[TokenomicsTextSizeKey.self] }
        set { self[TokenomicsTextSizeKey.self] = newValue }
    }
}

// MARK: - Scaled Font

/// Applies an explicit point size to text based on the current TextSize.
/// Exists because SwiftUI's `.dynamicTypeSize` barely moves semantic fonts on
/// macOS (xxLarge ≈ +1pt on body text) — not enough scaling for users who
/// actually need bigger text. This modifier gives us real +2pt / +4pt bumps.
///
/// Base sizes match macOS SF Pro defaults for each TextStyle. Weight defaults
/// match the style's implicit weight (.headline is semibold, the rest regular).
/// Callers can still chain `.fontWeight(...)` to override.
struct ScaledFontModifier: ViewModifier {
    let style: Font.TextStyle
    @Environment(\.tokenomicsTextSize) private var textSize

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: defaultWeight))
    }

    private var baseSize: CGFloat {
        switch style {
        case .caption2:    return 10
        case .caption:     return 10
        case .footnote:    return 10
        case .subheadline: return 11
        case .callout:     return 12
        case .body:        return 13
        case .headline:    return 13
        case .title3:      return 15
        case .title2:      return 17
        case .title:       return 22
        case .largeTitle:  return 26
        @unknown default:  return 13
        }
    }

    private var defaultWeight: Font.Weight {
        style == .headline ? .semibold : .regular
    }

    private var scaledSize: CGFloat {
        let addition: CGFloat
        switch textSize {
        case .compact: addition = 0
        case .medium:  addition = 2
        case .large:   addition = 4
        }
        return baseSize + addition
    }
}

extension View {
    /// Drop-in replacement for `.font(.caption)` etc. that scales with the
    /// popover text size preference.
    func scaledFont(_ style: Font.TextStyle) -> some View {
        modifier(ScaledFontModifier(style: style))
    }
}

/// Persists user preferences for multi-provider configuration
enum SettingsService {
    // UserDefaults.standard is documented as thread-safe by Apple
    nonisolated(unsafe) private static let defaults = UserDefaults.standard

    // MARK: - Onboarding

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - Text Size

    /// User-selected popover text size. Defaults to .compact so existing users
    /// see no change on upgrade — they can opt into Medium/Large if they want.
    static var textSize: TextSize {
        get {
            defaults.string(forKey: "textSize").flatMap { TextSize(rawValue: $0) } ?? .compact
        }
        set {
            defaults.set(newValue.rawValue, forKey: "textSize")
        }
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
