import SwiftUI

@main
struct TokenomicsApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @StateObject private var updaterService = UpdaterService()

    /// Width scales with visible tab count.
    /// Each tab: 12 icon + 5 gap + ~42 text + 24 h-padding = ~83pt.
    /// Fixed chrome: 16px popover padding × 2 + 2px tab bar padding × 2 = 36pt.
    /// Tab gaps: 2pt × (n-1).
    private var popoverWidth: CGFloat {
        let n = CGFloat(max(viewModel.visibleProviders.count, 1))
        let perTab: CGFloat = 83
        let chrome: CGFloat = 36
        let gaps = 2 * (n - 1)
        let computed = n * perTab + gaps + chrome
        return max(computed, 360)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel, updaterService: updaterService)
                .frame(width: popoverWidth)
        } label: {
            MenuBarLabel(viewModel: viewModel)
                .onAppear {
                    viewModel.startPolling()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar label — shows ring + percentage for one provider.
/// Smart mode picks the worst-of-N; pinned mode shows the user's choice.
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
                ringLabel
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.menuBarTooltip)
        .help(viewModel.menuBarTooltip)
    }

    // MARK: - Ring + Percentage

    @ViewBuilder
    private var ringLabel: some View {
        if let usage = activeUsage {
            if let longWindow = usage.longWindow {
                Image(nsImage: MenuBarRingsRenderer.image(
                    fiveHourFraction: usage.shortWindow.utilization / 100,
                    sevenDayFraction: longWindow.utilization / 100,
                    fiveHourPace: usage.shortWindow.pace,
                    sevenDayPace: longWindow.pace
                ))
            } else {
                Image(nsImage: MenuBarRingsRenderer.singleRingImage(
                    fraction: usage.shortWindow.utilization / 100,
                    pace: usage.shortWindow.pace
                ))
            }

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

    /// The usage snapshot to display: pinned provider if set, otherwise worst-of-N.
    private var activeUsage: ProviderUsageSnapshot? {
        if let pinned = viewModel.pinnedProviders.first,
           let usage = viewModel.providerStates[pinned]?.usage {
            return usage
        }
        return viewModel.worstOfNUsage()
    }
}
