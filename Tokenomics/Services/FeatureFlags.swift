import Foundation

/// Runtime feature flags for in-flight UX changes that need an easy rollback
/// while the work stabilizes. Backed by `UserDefaults` so flips persist across
/// app launches and the standard macOS `defaults` command is a fallback path:
///
///     defaults write com.robstout.tokenomics tokenomics.brandAggregation.enabled -bool true
///
/// Flags default to `false` — the new code path stays opt-in until the build
/// has been validated. A hidden Settings toggle (Option-held while opening
/// Settings) is the primary user-facing flip mechanism.
enum FeatureFlags {
    /// When true, the popover renders tabs by brand with per-pool sub-sections,
    /// the medium/large widgets render brand parent rows + per-pool sub-rows,
    /// and the Pin Tracker dropdown flattens to per-pool entries.
    ///
    /// When false (default), every surface keeps today's per-ProviderId
    /// rendering exactly as-is. Toggling the flag never alters underlying
    /// usage data — only how it's grouped for display.
    static var brandAggregation: Bool {
        get { UserDefaults.standard.bool(forKey: brandAggregationKey) }
        set { UserDefaults.standard.set(newValue, forKey: brandAggregationKey) }
    }

    static let brandAggregationKey = "tokenomics.brandAggregation.enabled"
}
