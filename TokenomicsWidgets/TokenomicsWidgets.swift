import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDataStore.WidgetSnapshot?
    let selectedProvider: WidgetProviderSelection
}

// MARK: - Timeline Provider (Configurable)

#if WIDGET_EXTENSION
struct UsageTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .placeholder, selectedProvider: .smart)
    }

    func snapshot(for configuration: SelectProviderIntent, in context: Context) async -> UsageEntry {
        UsageEntry(
            date: .now,
            snapshot: WidgetDataStore.read() ?? .placeholder,
            selectedProvider: configuration.provider
        )
    }

    func timeline(for configuration: SelectProviderIntent, in context: Context) async -> Timeline<UsageEntry> {
        let snapshot = WidgetDataStore.read()
        let entry = UsageEntry(
            date: .now,
            snapshot: snapshot,
            selectedProvider: configuration.provider
        )

        // Poll every 2 minutes — reloadAllTimelines() is unreliable from non-sandboxed host apps
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 2, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - Widget Configuration

struct TokenomicsWidget: Widget {
    let kind = "TokenomicsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectProviderIntent.self,
            provider: UsageTimelineProvider()
        ) { entry in
            TokenomicsWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetThemeBackground()
                }
        }
        .configurationDisplayName("AI Usage")
        .description("Track your AI coding tool usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Widget Bundle

@main
struct TokenomicsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenomicsWidget()
    }
}
#endif

// MARK: - Placeholder Data

extension WidgetDataStore.WidgetSnapshot {
    static let placeholder = WidgetDataStore.WidgetSnapshot(
        providers: [
            .init(
                id: "claude",
                displayName: "Claude Code",
                shortLabel: "C",
                shortWindow: .init(label: "5-Hour", utilization: 42, resetsAt: Date().addingTimeInterval(7200), windowDuration: 18000),
                longWindow: .init(label: "7-Day", utilization: 28, resetsAt: Date().addingTimeInterval(259200), windowDuration: 604800),
                planLabel: "Pro"
            ),
            .init(
                id: "codex",
                displayName: "Codex CLI",
                shortLabel: "X",
                shortWindow: .init(label: "5-Hour", utilization: 65, resetsAt: Date().addingTimeInterval(3600), windowDuration: 18000),
                longWindow: .init(label: "Context", utilization: 35, resetsAt: Date().addingTimeInterval(43200), windowDuration: 86400),
                planLabel: "Plus"
            ),
            .init(
                id: "gemini",
                displayName: "Google AI",
                shortLabel: "G",
                shortWindow: .init(label: "Tokens", utilization: 12, resetsAt: Date().addingTimeInterval(5400), windowDuration: 18000),
                longWindow: .init(label: "Requests", utilization: 8, resetsAt: Date().addingTimeInterval(172800), windowDuration: 604800),
                planLabel: "Free"
            ),
            .init(
                id: "copilot",
                displayName: "GitHub Copilot",
                shortLabel: "H",
                shortWindow: .init(label: "Chat", utilization: 3, resetsAt: Date().addingTimeInterval(14400), windowDuration: 18000),
                longWindow: .init(label: "Completions", utilization: 1, resetsAt: Date().addingTimeInterval(86400), windowDuration: 604800),
                planLabel: "Free"
            )
        ],
        updatedAt: Date()
    )
}
