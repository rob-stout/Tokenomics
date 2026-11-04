import AppIntents
import AppKit

// App Intents for Spotlight, Siri and Shortcuts. On macOS 26+ Spotlight runs
// these directly ("Refresh Tokenomics", "Check Claude usage"); older systems
// still get them in the Shortcuts app.

/// Polls every provider now — same as the popover's refresh button.
struct RefreshUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Usage"
    static let description = IntentDescription("Fetch the latest usage from every connected AI tool.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .tokenomicsBridgeRefreshRequested, object: nil)
        return .result(dialog: "Refreshing usage.")
    }
}

/// Opens the menu bar popover.
struct ShowUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Usage"
    static let description = IntentDescription("Open the Tokenomics menu bar popover.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Let Spotlight's panel close first; opening under it can no-op.
        try? await Task.sleep(for: .milliseconds(300))
        StatusItemPresenter.open()
        return .result()
    }
}

/// Answers "how much have I used?" without opening anything. Reads the same
/// snapshot the widgets do, so it reflects the last poll.
struct CheckUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Usage"
    static let description = IntentDescription("Show current usage for one AI tool, or the most-used one.")

    @Parameter(title: "Provider", default: .smart)
    var provider: WidgetProviderSelection

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let providers = WidgetDataStore.read()?.providers, !providers.isEmpty else {
            return .result(dialog: "No usage yet. Open Tokenomics to connect a tool.")
        }
        // Selection raw values match the snapshot's provider ids.
        let match = provider == .smart
            ? providers.max { $0.shortWindow.utilization < $1.shortWindow.utilization }
            : providers.first { $0.id == provider.rawValue }
        guard let match else {
            return .result(dialog: "That tool isn't connected in Tokenomics.")
        }

        var parts = ["\(match.shortWindow.label) \(Int(match.shortWindow.utilization))%"]
        if let long = match.longWindow {
            parts.append("\(long.label) \(Int(long.utilization))%")
        }
        return .result(dialog: "\(match.displayName): \(parts.joined(separator: ", ")).")
    }
}

struct TokenomicsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckUsageIntent(),
            phrases: [
                "Check \(.applicationName) usage",
                "Check \(\.$provider) usage in \(.applicationName)"
            ],
            shortTitle: "Check Usage",
            systemImageName: "gauge.with.dots.needle.33percent"
        )
        AppShortcut(
            intent: RefreshUsageIntent(),
            phrases: ["Refresh \(.applicationName)"],
            shortTitle: "Refresh Usage",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: ShowUsageIntent(),
            phrases: ["Show \(.applicationName)"],
            shortTitle: "Show Usage",
            systemImageName: "menubar.rectangle"
        )
    }
}
