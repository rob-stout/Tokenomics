import SwiftUI

/// Settings sub-screen showing all providers with pin toggles
struct AIConnectionsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var geminiPlan: GeminiPlan = SettingsService.geminiPlan ?? .free
    @State private var showingPATEntry = false
    @State private var patText = ""

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
                    Text("Tap a letter to pin it to the menu bar. Tap again to return to Smart mode, which shows the most urgent.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    .contentShape(Rectangle())
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

                if provider == .gemini && isConnected {
                    HStack(spacing: 2) {
                        ForEach(GeminiPlan.allCases, id: \.self) { plan in
                            let isActive = geminiPlan == plan
                            Button(action: {
                                geminiPlan = plan
                                SettingsService.geminiPlan = plan
                                viewModel.refresh()
                            }) {
                                Text(plan.displayLabel)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                    .background(isActive ? Color.white.opacity(0.1) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .foregroundStyle(isActive ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .padding(.top, 4)
                }
            }

            Spacer()

            // Action buttons for non-connected states
            switch connection {
            case .notInstalled:
                if provider.usesPATAuth {
                    Button("Connect") {
                        showingPATEntry = true
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
                    .help("Enter a GitHub Personal Access Token")
                } else {
                    Button("Install") {
                        provider.openInstallInTerminal()
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
                    .help("Opens Terminal to install \(provider.displayName)")
                }
            case .installedNoAuth:
                if provider.usesPATAuth {
                    Button("Connect") {
                        showingPATEntry = true
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
                    .help("Enter a GitHub Personal Access Token")
                } else {
                    Button("Sign In") {
                        provider.openLoginInTerminal()
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
                    .help("Opens Terminal to sign in")
                }
            case .authExpired:
                if provider.usesPATAuth {
                    Button("Reconnect") {
                        showingPATEntry = true
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
                    .help("Enter a new GitHub Personal Access Token")
                } else {
                    Button("Fix") {
                        provider.openLoginInTerminal()
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
                    .help("Opens Terminal to reconnect")
                }
            default:
                if provider == .copilot && isConnected {
                    Button("Disconnect") {
                        CopilotKeychainService.deletePAT()
                        viewModel.redetectProviders()
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
                } else {
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 10)
        .sheet(isPresented: $showingPATEntry) {
            patEntrySheet
        }
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

    // MARK: - PAT Entry Sheet

    private var patEntrySheet: some View {
        VStack(spacing: 16) {
            Text("Connect GitHub Copilot")
                .font(.headline)

            Text("Enter a fine-grained Personal Access Token with **Plan (read)** permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("ghp_...", text: $patText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            HStack {
                Button("Create Token") {
                    if let url = URL(string: "https://github.com/settings/personal-access-tokens/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    patText = ""
                    showingPATEntry = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Connect") {
                    let trimmed = patText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    CopilotKeychainService.savePAT(trimmed)
                    patText = ""
                    showingPATEntry = false
                    viewModel.redetectProviders()
                    viewModel.refresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(patText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
