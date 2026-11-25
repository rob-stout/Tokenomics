import Foundation

/// Pure rules for syncing which providers are switched on with the browser extension.
/// Same rule as the tab order: per provider, the change with the later timestamp wins.
enum ProviderVisibilitySync {

    /// The extension's settings that should replace the Mac's: newer than the Mac's own
    /// stamp, for providers the Mac knows. Providers only the extension has are skipped.
    static func incomingChanges(
        remote: [String: ProviderVisibilitySetting],
        local: [String: ProviderVisibilitySetting]
    ) -> [(id: ProviderId, setting: ProviderVisibilitySetting)] {
        remote
            .compactMap { raw, setting -> (id: ProviderId, setting: ProviderVisibilitySetting)? in
                guard let id = ProviderId(rawValue: raw) else { return nil }
                let mine = local[raw]?.lastChangedAt ?? .distantPast
                return setting.lastChangedAt > mine ? (id, setting) : nil
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// Before this sync existed, hiding a provider on the Mac recorded no timestamp.
    /// Stamp those once, at `now`, so a user's existing Mac choice isn't undone by an
    /// older setting from the extension. Providers that are showing stay unstamped:
    /// the user never chose anything for them on the Mac, so the extension's choice applies.
    static func seededStamps(
        hidden: Set<ProviderId>,
        existing: [String: ProviderVisibilitySetting],
        now: Date
    ) -> [String: ProviderVisibilitySetting] {
        var result = existing
        for id in hidden where result[id.rawValue] == nil {
            result[id.rawValue] = ProviderVisibilitySetting(enabled: false, lastChangedAt: now)
        }
        return result
    }
}
