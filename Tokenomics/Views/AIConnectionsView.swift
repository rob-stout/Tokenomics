import SwiftUI

/// Settings sub-screen showing all providers with pin toggles
struct AIConnectionsView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: { viewModel.showAIConnections = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Settings")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("AI Connections")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                // Invisible balance for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Settings")
                }
                .font(.caption)
                .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            VStack(spacing: 0) {
                ForEach(ProviderId.allCases) { provider in
                    connectionRow(for: provider)
                    if provider != ProviderId.allCases.last {
                        Divider()
                    }
                }

                // Hint text
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)
                    Text("Tap a letter to show its rings in the menu bar. When none are selected, Smart mode shows the most urgent.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func connectionRow(for provider: ProviderId) -> some View {
        let state = viewModel.providerStates[provider]
        let connection = state?.connection ?? .notInstalled
        let isConnected = connection.isConnected
        let isPinned = viewModel.isPinned(provider)

        HStack(spacing: 10) {
            // Provider icon — acts as pin toggle for connected providers
            Button(action: {
                if isConnected {
                    viewModel.togglePin(for: provider)
                }
            }) {
                Text(provider.shortLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 26, height: 26)
                    .background(iconBackground(connected: isConnected, pinned: isPinned))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(iconForeground(connected: isConnected, pinned: isPinned))
                    .opacity(connection == .notInstalled ? 0.3 : 1)
            }
            .buttonStyle(.plain)
            .disabled(!isConnected)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(connection == .notInstalled ? .secondary : .primary)

                Text(connection.statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor(connection))
            }

            Spacer()

            // Action buttons for error states
            switch connection {
            case .notInstalled:
                if let url = provider.installURL {
                    Link("Install", destination: url)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }
            case .authExpired:
                Button("Fix") {
                    // Copy login command to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(provider.loginCommand, forType: .string)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .buttonStyle(.plain)
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Icon Styling

    /// ON state: filled background like bar track
    /// OFF state: transparent with outline
    private func iconBackground(connected: Bool, pinned: Bool) -> Color {
        if connected && pinned {
            return Color(nsColor: .quaternaryLabelColor)
        }
        return .clear
    }

    private func iconForeground(connected: Bool, pinned: Bool) -> Color {
        if connected && pinned {
            return .primary
        }
        return .secondary
    }

    private func statusColor(_ connection: ProviderConnectionState) -> Color {
        switch connection {
        case .connected: return .green
        case .authExpired: return .orange
        default: return .secondary
        }
    }
}
