#if DEBUG
import SwiftUI
import WidgetKit

// MARK: - Widget Preview Helpers

/// Wraps widget entry views in a fixed frame matching actual widget sizes on macOS.
/// Lives in the main app target because Xcode previews don't work with extensionkit-extension targets.

private func widgetFrame(for family: WidgetFamily) -> (width: CGFloat, height: CGFloat) {
    switch family {
    case .systemSmall:  return (170, 170)
    case .systemMedium: return (364, 170)
    case .systemLarge:  return (364, 376)
    default:            return (364, 170)
    }
}

/// A container that simulates the widget background and size for preview purposes.
private struct WidgetPreviewContainer<Content: View>: View {
    let family: WidgetFamily
    let colorScheme: ColorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        let size = widgetFrame(for: family)
        let theme = WidgetTheme.current(for: colorScheme, renderingMode: .fullColor)

        content()
            .environment(\.widgetTheme, theme)
            .frame(width: size.width, height: size.height)
            .background(theme.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Sample Data

private let oneProvider = WidgetDataStore.WidgetSnapshot(
    providers: [
        .init(
            id: "claude",
            displayName: "Claude Code",
            shortLabel: "C",
            shortWindow: .init(label: "5-Hour", utilization: 42, resetsAt: Date().addingTimeInterval(7200), windowDuration: 18000),
            longWindow: .init(label: "7-Day", utilization: 28, resetsAt: Date().addingTimeInterval(259200), windowDuration: 604800),
            planLabel: "Pro"
        )
    ],
    updatedAt: Date()
)

private let twoProviders = WidgetDataStore.WidgetSnapshot(
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
        )
    ],
    updatedAt: Date()
)

private let threeProviders = WidgetDataStore.WidgetSnapshot(
    providers: [
        .init(
            id: "claude",
            displayName: "Claude Code",
            shortLabel: "C",
            shortWindow: .init(label: "5-Hour", utilization: 78, resetsAt: Date().addingTimeInterval(7200), windowDuration: 18000),
            longWindow: .init(label: "7-Day", utilization: 45, resetsAt: Date().addingTimeInterval(259200), windowDuration: 604800),
            planLabel: "Pro"
        ),
        .init(
            id: "copilot",
            displayName: "GitHub Copilot",
            shortLabel: "G",
            shortWindow: .init(label: "Monthly", utilization: 32, resetsAt: Date().addingTimeInterval(86400), windowDuration: 2592000),
            longWindow: nil,
            planLabel: "Pro"
        ),
        .init(
            id: "gemini",
            displayName: "Gemini CLI",
            shortLabel: "G",
            shortWindow: .init(label: "Daily", utilization: 55, resetsAt: Date().addingTimeInterval(14400), windowDuration: 86400),
            longWindow: .init(label: "Monthly", utilization: 12, resetsAt: Date().addingTimeInterval(604800), windowDuration: 2592000),
            planLabel: "Free"
        )
    ],
    updatedAt: Date()
)

private let fourProviders = WidgetDataStore.WidgetSnapshot(
    providers: [
        .init(id: "claude", displayName: "Claude Code", shortLabel: "C",
              shortWindow: .init(label: "5-Hour", utilization: 42, resetsAt: Date().addingTimeInterval(7200), windowDuration: 18000),
              longWindow: .init(label: "7-Day", utilization: 28, resetsAt: Date().addingTimeInterval(259200), windowDuration: 604800),
              planLabel: "Pro"),
        .init(id: "codex", displayName: "Codex CLI", shortLabel: "X",
              shortWindow: .init(label: "5-Hour", utilization: 65, resetsAt: Date().addingTimeInterval(3600), windowDuration: 18000),
              longWindow: .init(label: "Context", utilization: 35, resetsAt: Date().addingTimeInterval(43200), windowDuration: 86400),
              planLabel: "Plus"),
        .init(id: "copilot", displayName: "GitHub Copilot", shortLabel: "G",
              shortWindow: .init(label: "Monthly", utilization: 32, resetsAt: Date().addingTimeInterval(86400), windowDuration: 2592000),
              longWindow: nil,
              planLabel: "Pro"),
        .init(id: "gemini", displayName: "Gemini CLI", shortLabel: "G",
              shortWindow: .init(label: "Daily", utilization: 55, resetsAt: Date().addingTimeInterval(14400), windowDuration: 86400),
              longWindow: .init(label: "Monthly", utilization: 12, resetsAt: Date().addingTimeInterval(604800), windowDuration: 2592000),
              planLabel: "Free"),
    ],
    updatedAt: Date()
)

private let fiveProviders = WidgetDataStore.WidgetSnapshot(
    providers: Array(fourProviders.providers) + [
        .init(id: "cursor", displayName: "Cursor", shortLabel: "Cu",
              shortWindow: .init(label: "Monthly", utilization: 81, resetsAt: Date().addingTimeInterval(172800), windowDuration: 2592000),
              longWindow: nil,
              planLabel: "Pro"),
    ],
    updatedAt: Date()
)

private let sixProviders = WidgetDataStore.WidgetSnapshot(
    providers: Array(fiveProviders.providers) + [
        .init(id: "elevenlabs", displayName: "ElevenLabs", shortLabel: "E",
              shortWindow: .init(label: "Monthly", utilization: 15, resetsAt: Date().addingTimeInterval(604800), windowDuration: 2592000),
              longWindow: nil,
              planLabel: "Creator"),
    ],
    updatedAt: Date()
)

private let sevenProviders = WidgetDataStore.WidgetSnapshot(
    providers: Array(sixProviders.providers) + [
        .init(id: "runway", displayName: "Runway", shortLabel: "R",
              shortWindow: .init(label: "Monthly", utilization: 48, resetsAt: Date().addingTimeInterval(345600), windowDuration: 2592000),
              longWindow: nil,
              planLabel: "Standard"),
    ],
    updatedAt: Date()
)

private let eightProviders = WidgetDataStore.WidgetSnapshot(
    providers: [
        .init(id: "claude", displayName: "Claude Code", shortLabel: "C",
              shortWindow: .init(label: "5-Hour", utilization: 42, resetsAt: Date().addingTimeInterval(7200), windowDuration: 18000),
              longWindow: .init(label: "7-Day", utilization: 28, resetsAt: Date().addingTimeInterval(259200), windowDuration: 604800),
              planLabel: "Pro"),
        .init(id: "codex", displayName: "Codex CLI", shortLabel: "X",
              shortWindow: .init(label: "5-Hour", utilization: 65, resetsAt: Date().addingTimeInterval(3600), windowDuration: 18000),
              longWindow: .init(label: "Context", utilization: 35, resetsAt: Date().addingTimeInterval(43200), windowDuration: 86400),
              planLabel: "Plus"),
        .init(id: "copilot", displayName: "GitHub Copilot", shortLabel: "G",
              shortWindow: .init(label: "Monthly", utilization: 32, resetsAt: Date().addingTimeInterval(86400), windowDuration: 2592000),
              longWindow: nil,
              planLabel: "Pro"),
        .init(id: "gemini", displayName: "Gemini CLI", shortLabel: "G",
              shortWindow: .init(label: "Daily", utilization: 55, resetsAt: Date().addingTimeInterval(14400), windowDuration: 86400),
              longWindow: .init(label: "Monthly", utilization: 12, resetsAt: Date().addingTimeInterval(604800), windowDuration: 2592000),
              planLabel: "Free"),
        .init(id: "cursor", displayName: "Cursor", shortLabel: "Cu",
              shortWindow: .init(label: "Monthly", utilization: 81, resetsAt: Date().addingTimeInterval(172800), windowDuration: 2592000),
              longWindow: nil,
              planLabel: "Pro"),
        .init(id: "elevenlabs", displayName: "ElevenLabs", shortLabel: "E",
              shortWindow: .init(label: "Monthly", utilization: 15, resetsAt: Date().addingTimeInterval(604800), windowDuration: 2592000),
              longWindow: nil,
              planLabel: "Creator"),
        .init(id: "runway", displayName: "Runway", shortLabel: "R",
              shortWindow: .init(label: "Monthly", utilization: 48, resetsAt: Date().addingTimeInterval(345600), windowDuration: 2592000),
              longWindow: nil,
              planLabel: "Standard"),
        .init(id: "stableDiffusion", displayName: "Stable Diffusion", shortLabel: "SD",
              shortWindow: .init(label: "Daily", utilization: 22, resetsAt: Date().addingTimeInterval(28800), windowDuration: 86400),
              longWindow: nil,
              planLabel: "Core"),
    ],
    updatedAt: Date()
)

// MARK: - Brand-aggregation sample data
//
// Built through the REAL `WidgetDataStore.makeEntries` bake so the previews show
// exactly what ships: poolLabel labels ("Codex CLI", "Gemini (app)") + brandId
// grouping. This is the layout that struggled before — multi-pool brands render a
// brand header with indented per-pool sub-rows.

private func sampleUsage(_ short: Double, long: Double? = nil) -> ProviderUsageSnapshot {
    ProviderUsageSnapshot(
        shortWindow: WindowUsage(label: "5-Hour Window", utilization: short,
                                 resetsAt: Date().addingTimeInterval(7200), windowDuration: 18000),
        longWindow: long.map {
            WindowUsage(label: "Weekly", utilization: $0,
                        resetsAt: Date().addingTimeInterval(259200), windowDuration: 604800)
        },
        planLabel: "Pro",
        extraUsage: nil,
        creditsBalance: nil
    )
}

/// Brand-aggregated snapshot for the given pools, baked via the production path.
private func brandSnapshot(_ ids: [ProviderId]) -> WidgetDataStore.WidgetSnapshot {
    let pairs = ids.map { ($0, sampleUsage(Double(($0.rawValue.count * 13) % 100),
                                            long: Double(($0.rawValue.count * 7) % 100))) }
    return WidgetDataStore.WidgetSnapshot(
        providers: WidgetDataStore.makeEntries(providers: pairs),
        updatedAt: Date(),
        brandAggregationEnabled: true
    )
}

// Two multi-pool brands: OpenAI (ChatGPT + Codex CLI), Google (Gemini app + CLI).
private let brandsMultiPool = brandSnapshot([.chatgpt, .codex, .geminiConsumer, .gemini])
// Mixed: single-pool Anthropic + both multi-pool brands + single-pool Cursor.
private let brandsMixed = brandSnapshot([.claude, .chatgpt, .codex, .geminiConsumer, .gemini, .cursor])

// MARK: - Previews

// ── Brand aggregation (the new multi-pool layout) ──

#Preview("Brand — Medium — multi-pool") {
    WidgetPreviewContainer(family: .systemMedium, colorScheme: .dark) {
        MediumWidgetView(entry: UsageEntry(date: .now, snapshot: brandsMultiPool, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Brand — Large — multi-pool") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .dark) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: brandsMultiPool, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Brand — Large — mixed") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .dark) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: brandsMixed, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Brand — Large — mixed — light") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .light) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: brandsMixed, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

// ── Per-provider (flag-off) layout ──

#Preview("Small — Dark") {
    WidgetPreviewContainer(family: .systemSmall, colorScheme: .dark) {
        SmallWidgetView(entry: UsageEntry(date: .now, snapshot: twoProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Small — Light") {
    WidgetPreviewContainer(family: .systemSmall, colorScheme: .light) {
        SmallWidgetView(entry: UsageEntry(date: .now, snapshot: twoProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Medium — 1 Provider") {
    WidgetPreviewContainer(family: .systemMedium, colorScheme: .dark) {
        MediumWidgetView(entry: UsageEntry(date: .now, snapshot: oneProvider, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Medium — 2 Providers") {
    WidgetPreviewContainer(family: .systemMedium, colorScheme: .dark) {
        MediumWidgetView(entry: UsageEntry(date: .now, snapshot: twoProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Medium — 3 Providers") {
    WidgetPreviewContainer(family: .systemMedium, colorScheme: .dark) {
        MediumWidgetView(entry: UsageEntry(date: .now, snapshot: threeProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Medium — 4 Providers") {
    WidgetPreviewContainer(family: .systemMedium, colorScheme: .dark) {
        MediumWidgetView(entry: UsageEntry(date: .now, snapshot: fourProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Large — 2 Providers") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .dark) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: twoProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Large — 3 Providers") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .dark) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: threeProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Large — 4 Providers") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .dark) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: fourProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Large — 5 Providers") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .dark) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: fiveProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Large — 6 Providers") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .dark) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: sixProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Large — 7 Providers") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .dark) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: sevenProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Large — 8 Providers") {
    WidgetPreviewContainer(family: .systemLarge, colorScheme: .dark) {
        LargeWidgetView(entry: UsageEntry(date: .now, snapshot: eightProviders, selectedProvider: .smart))
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("No Data") {
    WidgetPreviewContainer(family: .systemSmall, colorScheme: .dark) {
        NoDataView()
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#endif
