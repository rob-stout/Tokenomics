import Foundation

/// Runtime feature flags for in-flight UX changes that need an easy rollback
/// while the work stabilizes. Backed by `UserDefaults` so flips persist across
/// app launches and the standard macOS `defaults` command is a fallback path:
///
///     defaults write com.robstout.tokenomics tokenomics.brandAggregation.enabled -bool true
///
/// Brand aggregation shipped ON by default in 2.10.4 (Settings groups by company,
/// and so does the browser extension); users can turn it off in Settings →
/// Preferences → "Group by company".
enum FeatureFlags {
    /// When true, the popover renders tabs by brand with per-pool sub-sections,
    /// the medium/large widgets render brand parent rows + per-pool sub-rows,
    /// and the Pin Tracker dropdown flattens to per-pool entries.
    ///
    /// When false (user opted out), every surface keeps the per-ProviderId
    /// rendering. Toggling the flag never alters underlying
    /// usage data — only how it's grouped for display.
    static var brandAggregation: Bool {
        // On unless the user turned it off (Settings → Preferences → Group by company).
        get { UserDefaults.standard.object(forKey: brandAggregationKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: brandAggregationKey) }
    }

    static let brandAggregationKey = "tokenomics.brandAggregation.enabled"
}
