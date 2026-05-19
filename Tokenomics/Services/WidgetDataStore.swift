import Foundation
import WidgetKit

/// Shares usage data between the main app and widget extension via the App Group container.
///
/// Uses file-based storage instead of UserDefaults to avoid CFPrefs issues
/// when the main app is non-sandboxed but the widget extension is sandboxed.
enum WidgetDataStore {
    static let appGroupId = "group.com.robstout.tokenomics"

    /// Shared file URL inside the App Group container
    private static var sharedFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("widget-data.json")
    }

    // MARK: - Shared Data Model

    /// Lightweight struct for widget consumption — contains only what widgets need
    struct WidgetSnapshot: Codable {
        let providers: [ProviderEntry]
        let updatedAt: Date
        /// Whether the brand-aggregation layout is enabled at snapshot time.
        /// Stamped by the main app so the widget extension (a separate process
        /// without access to the app's UserDefaults domain) can gate the
        /// brand-grouping rendering path correctly.
        ///
        /// Nil in legacy snapshots written before 5.6.B — widget treats nil
        /// as false (flag-off) so the old layout is preserved.
        let brandAggregationEnabled: Bool?

        // Backward-compatible init: callers that don't supply brandAggregationEnabled
        // (tests, placeholder, legacy decode) default to nil → flag off.
        init(providers: [ProviderEntry], updatedAt: Date, brandAggregationEnabled: Bool? = nil) {
            self.providers = providers
            self.updatedAt = updatedAt
            self.brandAggregationEnabled = brandAggregationEnabled
        }

        /// Convenience accessor — defaults nil to false so rendering code
        /// can use this without optional gymnastics.
        var isBrandAggregationEnabled: Bool {
            brandAggregationEnabled ?? false
        }

        struct ProviderEntry: Codable {
            let id: String
            let displayName: String
            let shortLabel: String
            let shortWindow: WindowEntry
            /// Nil for providers that only expose a single usage metric.
            let longWindow: WindowEntry?
            let planLabel: String
            /// Brand grouping key — set to the parent BrandId.rawValue when
            /// brand-aggregation rendering is active. Nil in legacy snapshots
            /// so existing widgets decode cleanly (no migration needed).
            ///
            /// The widget renderer reads this only when FeatureFlags.brandAggregation
            /// is on; the flag-off code path never touches this field.
            let brandId: String?

            // Backward-compatible memberwise init so all existing call sites that
            // omit brandId keep compiling without changes.
            init(
                id: String,
                displayName: String,
                shortLabel: String,
                shortWindow: WindowEntry,
                longWindow: WindowEntry?,
                planLabel: String,
                brandId: String? = nil
            ) {
                self.id = id
                self.displayName = displayName
                self.shortLabel = shortLabel
                self.shortWindow = shortWindow
                self.longWindow = longWindow
                self.planLabel = planLabel
                self.brandId = brandId
            }
        }

        struct WindowEntry: Codable {
            let label: String
            let utilization: Double
            let resetsAt: Date
            let windowDuration: TimeInterval

            /// Abbreviated reset time for widget display (e.g. "2h 30m", "Tomorrow")
            var shortTimeUntilReset: String {
                let interval = resetsAt.timeIntervalSinceNow
                guard interval > 0 else { return "Now" }

                let hours = Int(interval) / 3600
                let minutes = (Int(interval) % 3600) / 60

                if hours >= 24 {
                    let calendar = Calendar.current
                    if calendar.isDateInToday(resetsAt) {
                        return "Today"
                    } else if calendar.isDateInTomorrow(resetsAt) {
                        return "Tomorrow"
                    } else {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "EEE"
                        return formatter.string(from: resetsAt)
                    }
                } else if hours > 0 {
                    return "\(hours)h \(minutes)m"
                } else {
                    return "\(minutes)m"
                }
            }

            /// Pace: how far through the window we are (0–1)
            var pace: Double {
                guard windowDuration > 0 else { return 0 }
                let remaining = max(resetsAt.timeIntervalSinceNow, 0)
                let elapsed = windowDuration - min(remaining, windowDuration)
                return min(max(elapsed / windowDuration, 0), 1)
            }
        }
    }

    // MARK: - Write (Main App Only)

    /// Writes the current provider states to shared storage for widget consumption.
    /// Call this after each successful provider fetch.
    ///
    /// This method uses main app types (ProviderId, ProviderUsageSnapshot) and is
    /// not compiled in the widget extension target.
    #if !WIDGET_EXTENSION
    static func write(providers: [(ProviderId, ProviderUsageSnapshot)]) {
        let entries = providers.map { id, snapshot in
            WidgetSnapshot.ProviderEntry(
                id: id.rawValue,
                displayName: id.displayName,
                shortLabel: id.shortLabel,
                shortWindow: .init(
                    label: widgetLabel(snapshot.shortWindow.label),
                    utilization: snapshot.shortWindow.utilization,
                    resetsAt: snapshot.shortWindow.resetsAt,
                    windowDuration: snapshot.shortWindow.windowDuration
                ),
                longWindow: snapshot.longWindow.map { long in
                    .init(
                        label: widgetLabel(long.label),
                        utilization: long.utilization,
                        resetsAt: long.resetsAt,
                        windowDuration: long.windowDuration
                    )
                },
                planLabel: snapshot.planLabel,
                // Stamp the brand key on every entry so the medium/large
                // brand-aggregation renderer can group sub-rows by parent.
                // The flag-off code path ignores this field entirely.
                brandId: id.brand.rawValue
            )
        }

        let widgetSnapshot = WidgetSnapshot(
            providers: entries,
            updatedAt: Date(),
            // Stamp the flag so the widget extension (a separate process) can
            // read the value that was current when the snapshot was written.
            brandAggregationEnabled: FeatureFlags.brandAggregation
        )

        guard let url = sharedFileURL,
              let data = try? JSONEncoder().encode(widgetSnapshot) else { return }

        // Ensure the directory exists
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try? data.write(to: url, options: .atomic)

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Shorten labels for widget display: "5-Hour Window" → "5-Hour", "Tokens Today" → "Tokens"
    private static func widgetLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: " Window", with: "")
            .replacingOccurrences(of: " Today", with: "")
    }
    #endif

    // MARK: - Read (Widget Extension)

    /// Reads the latest snapshot from shared storage.
    static func read() -> WidgetSnapshot? {
        guard let url = sharedFileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}
