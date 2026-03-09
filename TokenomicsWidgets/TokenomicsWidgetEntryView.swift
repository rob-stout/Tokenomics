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

/// Shows all connected providers with both usage windows — mirrors the popover mental model
struct MediumWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.providers.isEmpty {
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
                .padding(.bottom, 8)

                // Provider rows
                ForEach(Array(snapshot.providers.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        Divider()
                            .padding(.vertical, 4)
                    }
                    providerRow(provider)
                }

                Spacer(minLength: 0)
            }
        } else {
            noDataView
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: WidgetDataStore.WidgetSnapshot.ProviderEntry) -> some View {
        HStack(spacing: 12) {
            // Provider label
            Text(provider.shortLabel)
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))

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

            // Long window bar
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(provider.longWindow.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(provider.longWindow.utilization))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                WidgetProgressBar(
                    utilization: provider.longWindow.utilization,
                    pace: provider.longWindow.pace
                )
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

#Preview("No Data", as: .systemSmall) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: nil, selectedProvider: .smart)
}
