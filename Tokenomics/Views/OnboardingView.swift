import SwiftUI

/// First-run experience showing auto-detected providers
struct OnboardingView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Activity rings illustration
                Image(nsImage: MenuBarRingsRenderer.image(
                    fiveHourFraction: 0.7,
                    sevenDayFraction: 0.45,
                    fiveHourPace: 0.5,
                    sevenDayPace: 0.5
                ))
                .scaleEffect(2.5)
                .frame(width: 44, height: 44)
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text("Track your AI coding usage")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("at a glance from the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Provider connection list
                VStack(spacing: 0) {
                    ForEach(ProviderId.allCases) { provider in
                        connectionRow(for: provider)
                        if provider != ProviderId.allCases.last {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 4)

                Button("Get Started") {
                    viewModel.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func connectionRow(for provider: ProviderId) -> some View {
        let state = viewModel.providerStates[provider]
        let connection = state?.connection ?? .notInstalled
        let isConnected = connection.isConnected

        HStack(spacing: 10) {
            // Provider icon — filled if connected, dimmed if not installed
            Text(provider.shortLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 26, height: 26)
                .background(isConnected ? Color(nsColor: .quaternaryLabelColor) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(isConnected ? .primary : .tertiary)
                .opacity(connection == .notInstalled ? 0.3 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isConnected ? .primary : .secondary)

                Text(connectionStatusText(connection))
                    .font(.caption2)
                    .foregroundStyle(connectionStatusColor(connection))
            }

            Spacer()

            if case .notInstalled = connection {
                if let url = provider.installURL {
                    Link("Install", destination: url)
                        .font(.caption2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func connectionStatusText(_ connection: ProviderConnectionState) -> String {
        switch connection {
        case .connected: return "Connected"
        case .notInstalled: return "Not installed"
        case .installedNoAuth: return "Not signed in"
        case .authExpired: return "Auth expired"
        case .unavailable(let reason): return reason
        }
    }

    private func connectionStatusColor(_ connection: ProviderConnectionState) -> Color {
        switch connection {
        case .connected: return .green
        case .authExpired: return .orange
        default: return .secondary
        }
    }
}
