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
            MenuBarLabel(
                fiveHourUtilization: viewModel.fiveHourUtilization,
                sevenDayUtilization: viewModel.sevenDayUtilization,
                fiveHourPace: viewModel.fiveHourPace,
                sevenDayPace: viewModel.sevenDayPace,
                state: viewModel.usageState
            )
            .onAppear {
                viewModel.startPolling()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar label — two concentric rings + 5-hour percentage text.
///
/// Error and unauthenticated states fall back to SF Symbols (no rings) because
/// there's no meaningful utilization data to visualize.
struct MenuBarLabel: View {
    let fiveHourUtilization: Double
    let sevenDayUtilization: Double
    let fiveHourPace: Double
    let sevenDayPace: Double
    let state: UsageState

    private var helpText: String {
        switch state {
        case .unauthenticated:
            return "Tokenomics — not signed in"
        case .error:
            return "Tokenomics — connection error"
        case .loading:
            return "Tokenomics — loading..."
        default:
            return "5-hour: \(Int(fiveHourUtilization))%  |  7-day: \(Int(sevenDayUtilization))%"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            switch state {
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.red)

            case .unauthenticated:
                Image(systemName: "person.crop.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.secondary)

            default:
                Image(nsImage: MenuBarRingsRenderer.image(
                    fiveHourFraction: fiveHourUtilization / 100,
                    sevenDayFraction: sevenDayUtilization / 100,
                    fiveHourPace: fiveHourPace,
                    sevenDayPace: sevenDayPace
                ))
            }

            // Percentage text next to the rings — the primary at-a-glance number.
            // Hidden for error/unauthenticated since the icon alone communicates state.
            switch state {
            case .error, .unauthenticated:
                EmptyView()
            case .loading:
                Text("—")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .padding(.leading, 6)
            default:
                Text("\(Int(fiveHourUtilization))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .padding(.leading, 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
        .help(helpText)
    }
}
