import SwiftUI
import WidgetKit

/// Routes to the correct widget view based on widget family size
struct TokenomicsWidgetEntryView: View {
    let entry: UsageEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget (Configurable: Smart or Specific Provider)

/// Shows a single provider's short window usage as a ring.
/// In Smart mode, picks the provider with highest utilization.
struct SmallWidgetView: View {
    let entry: UsageEntry

    private var displayProvider: WidgetDataStore.WidgetSnapshot.ProviderEntry? {
        guard let providers = entry.snapshot?.providers, !providers.isEmpty else { return nil }

        switch entry.selectedProvider {
        case .smart:
            // Worst-of-N: highest short window utilization
            return providers.max(by: { $0.shortWindow.utilization < $1.shortWindow.utilization })
        case .claude:
            return providers.first(where: { $0.id == "claude" })
        case .copilot:
            return providers.first(where: { $0.id == "copilot" })
        case .cursor:
            return providers.first(where: { $0.id == "cursor" })
        case .codex:
            return providers.first(where: { $0.id == "codex" })
        case .gemini:
            return providers.first(where: { $0.id == "gemini" })
        }
    }

    var body: some View {
        if let provider = displayProvider {
            VStack(spacing: 6) {
                // Ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: min(provider.shortWindow.utilization / 100.0, 1.0))
                        .stroke(
                            ringColor(for: provider.shortWindow.utilization),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 56, height: 56)
                .overlay {
                    Text("\(Int(provider.shortWindow.utilization))%")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }

                Text(provider.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(provider.shortWindow.shortTimeUntilReset)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            noDataView
        }
    }
}

// MARK: - Medium Widget (Multi-Provider Dashboard — Concept B)

/// Shows all connected providers with both usage windows — mirrors the popover mental model.
/// Uses spacious rows for 1–2 providers; compact rows at 3+ to fit the limited height.
struct MediumWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.providers.isEmpty {
            let useCompact = snapshot.providers.count >= 3
            let maxVisible = 4
            let visibleProviders = Array(snapshot.providers.prefix(maxVisible))
            let overflowCount = snapshot.providers.count - maxVisible

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Tokenomics")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let updatedAt = entry.snapshot?.updatedAt {
                        Text(updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, useCompact ? 8 : 10)

                // Provider rows
                VStack(alignment: .leading, spacing: useCompact ? 16 : 14) {
                    ForEach(visibleProviders, id: \.id) { provider in
                        if useCompact {
                            CompactProviderRow(provider: provider)
                        } else {
                            LargeProviderRow(provider: provider)
                        }
                    }
                }

                if overflowCount > 0 {
                    Spacer(minLength: 4)
                    Text("+\(overflowCount) more in app")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Spacer(minLength: 0)
            }
            .padding(4)
        } else {
            noDataView
        }
    }
}

// MARK: - Large Widget (Spacious Multi-Provider Dashboard)

/// Full-height widget. Uses spacious rows for 1–3 providers; falls back to compact rows at 4+
/// to avoid overflow, since widgets can't scroll.
struct LargeWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.providers.isEmpty {
            let useCompact = snapshot.providers.count >= 4

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Tokenomics")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let updatedAt = entry.snapshot?.updatedAt {
                        Text(updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, useCompact ? 10 : 12)

                // Provider rows — spacious at 3 or fewer, compact at 4+
                VStack(alignment: .leading, spacing: useCompact ? 20 : 14) {
                    ForEach(snapshot.providers, id: \.id) { provider in
                        if useCompact {
                            CompactProviderRow(provider: provider)
                        } else {
                            LargeProviderRow(provider: provider)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(4)
        } else {
            noDataView
        }
    }
}

// MARK: - Provider Row Views

/// Compact single-line row: badge | short window bar | long window bar.
/// Used by MediumWidgetView and LargeWidgetView (4+ providers).
private struct CompactProviderRow: View {
    let provider: WidgetDataStore.WidgetSnapshot.ProviderEntry

    var body: some View {
        HStack(spacing: 12) {
            // Provider icon
            providerIcon(provider.id)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)

            // Short window bar
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(provider.shortWindow.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(provider.shortWindow.utilization))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                WidgetProgressBar(
                    utilization: provider.shortWindow.utilization,
                    pace: provider.shortWindow.pace
                )
            }

            // Long window bar — only shown when the provider exposes two usage windows
            if let longWindow = provider.longWindow {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(longWindow.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(longWindow.utilization))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }

                    WidgetProgressBar(
                        utilization: longWindow.utilization,
                        pace: longWindow.pace
                    )
                }
            }
        }
    }
}

/// Spacious row with a header line (name + plan) plus separate bar rows per window.
/// Used by LargeWidgetView when there are 3 or fewer providers.
private struct LargeProviderRow: View {
    let provider: WidgetDataStore.WidgetSnapshot.ProviderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider name + plan
            HStack(spacing: 10) {
                providerIcon(provider.id)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)

                Text(provider.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text(provider.planLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Short window
            HStack(spacing: 8) {
                Text(provider.shortWindow.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)

                WidgetProgressBar(
                    utilization: provider.shortWindow.utilization,
                    pace: provider.shortWindow.pace
                )

                Text("\(Int(provider.shortWindow.utilization))%")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }

            // Long window
            if let longWindow = provider.longWindow {
                HStack(spacing: 8) {
                    Text(longWindow.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)

                    WidgetProgressBar(
                        utilization: longWindow.utilization,
                        pace: longWindow.pace
                    )

                    Text("\(Int(longWindow.utilization))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Shared Components

struct WidgetProgressBar: View {
    let utilization: Double
    let pace: Double

    private var barColor: Color {
        ringColor(for: utilization)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4)

                Capsule()
                    .fill(barColor.opacity(0.6))
                    .frame(
                        width: geometry.size.width * min(max(utilization / 100.0, 0), 1),
                        height: 4
                    )
            }
        }
        .frame(height: 4)
    }
}

/// Load a provider icon PNG from the widget extension bundle
func providerIcon(_ id: String) -> Image {
    let name = "\(id.prefix(1).uppercased())\(id.dropFirst())-white"
    if let nsImage = Bundle.main.image(forResource: name) {
        return Image(nsImage: nsImage)
    }
    return Image(systemName: "questionmark.square")
}

/// Color based on utilization level — matches main app's UsageState
func ringColor(for utilization: Double) -> Color {
    switch utilization {
    case 0..<70: return .white
    case 70..<90: return .orange
    default: return .red
    }
}

/// Shown when no provider data is available
private var noDataView: some View {
    VStack(spacing: 6) {
        Image(systemName: "chart.bar.doc.horizontal")
            .font(.title2)
            .foregroundStyle(.secondary)
        Text("Open Tokenomics to sync")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Previews

#Preview("Small — Smart", as: .systemSmall) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, selectedProvider: .smart)
}

#Preview("Small — Claude", as: .systemSmall) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, selectedProvider: .claude)
}

#Preview("Medium", as: .systemMedium) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, selectedProvider: .smart)
}

#Preview("Large", as: .systemLarge) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, selectedProvider: .smart)
}

#Preview("No Data", as: .systemSmall) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: nil, selectedProvider: .smart)
}
