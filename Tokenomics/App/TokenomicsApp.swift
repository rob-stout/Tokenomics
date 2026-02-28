import SwiftUI

@main
struct TokenomicsApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @StateObject private var updaterService = UpdaterService()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel, updaterService: updaterService)
                .frame(width: 320)
        } label: {
            MenuBarLabel(viewModel: viewModel)
                .onAppear {
                    viewModel.startPolling()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar label — supports Smart mode (single worst-of-N ring set)
/// and Individual mode (one ring set per pinned provider with initial letter).
struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 0) {
            switch viewModel.menuBarState {
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.red)

            case .unauthenticated:
                Image(systemName: "person.crop.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.secondary)

            default:
                if viewModel.isSmartMode || viewModel.pinnedProviders.isEmpty {
                    smartModeLabel
                } else {
                    individualModeLabel
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.menuBarTooltip)
        .help(viewModel.menuBarTooltip)
    }

    // MARK: - Smart Mode (worst-of-N, single ring set)

    @ViewBuilder
    private var smartModeLabel: some View {
        if let usage = viewModel.worstOfNUsage() {
            Image(nsImage: MenuBarRingsRenderer.image(
                fiveHourFraction: usage.shortWindow.utilization / 100,
                sevenDayFraction: usage.longWindow.utilization / 100,
                fiveHourPace: usage.shortWindow.pace,
                sevenDayPace: usage.longWindow.pace
            ))

            Text("\(Int(usage.shortWindow.utilization))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .padding(.leading, 6)
        } else {
            Text("—")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .padding(.leading, 6)
        }
    }

    // MARK: - Individual Mode (one ring set per pinned provider)

    @ViewBuilder
    private var individualModeLabel: some View {
        let pinned = ProviderId.allCases.filter { viewModel.isPinned($0) }

        ForEach(Array(pinned.enumerated()), id: \.element) { index, provider in
            if index > 0 {
                Spacer().frame(width: 8)
            }

            providerRingSet(provider)
        }
    }

    @ViewBuilder
    private func providerRingSet(_ provider: ProviderId) -> some View {
        if let ringData = viewModel.menuBarRingData(for: provider) {
            // Initial letter
            Text(provider.shortLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.secondary)

            Image(nsImage: MenuBarRingsRenderer.image(
                fiveHourFraction: ringData.fiveHour / 100,
                sevenDayFraction: ringData.sevenDay / 100,
                fiveHourPace: ringData.fiveHourPace,
                sevenDayPace: ringData.sevenDayPace
            ))

            Text("\(Int(ringData.fiveHour))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .padding(.leading, 2)
        } else {
            // Auth error — show initial + warning glyph
            Text(provider.shortLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.secondary)

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(Color.orange)
        }
    }
}
