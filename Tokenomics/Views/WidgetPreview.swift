2#if DEBUG
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

// MARK: - Previews

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
