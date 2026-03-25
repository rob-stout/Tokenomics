import SwiftUI

/// Settings sub-screen showing all providers grouped by category with connect/disconnect controls
struct AIConnectionsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var geminiPlan: GeminiPlan = SettingsService.geminiPlan ?? .free
    @State private var showingPATEntry = false
    @State private var patText = ""
    @State private var apiKeyEntryProvider: ProviderId?
    @State private var apiKeyText = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ProviderId.ProviderCategory.allCases, id: \.self) { category in
                        let providersInCategory = ProviderId.allCases.filter { $0.category == category }
                        sectionHeader(category.rawValue)
                        VStack(spacing: 0) {
                            ForEach(providersInCategory, id: \.self) { provider in
                                connectionRow(
                                    for: provider,
                                    isLast: provider == providersInCategory.last
                                )
                            }
                        }
                        .padding(.bottom, 12)
                    }

                    // Hint text
                    Text("Toggle to show or hide providers. Reorder in the main view.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .sheet(item: $apiKeyEntryProvider) { _ in
            apiKeyEntrySheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { viewModel.showAIConnections = false }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Settings")
                }
                .font(.caption)
                .padding(.vertical, 4)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Text("Providers")
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
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Connection Row

    @ViewBuilder
    private func connectionRow(for provider: ProviderId, isLast: Bool = false) -> some View {
        let state = viewModel.providerStates[provider]
        let connection = state?.connection ?? .notInstalled
        let isConnected = connection.isConnected
        let isHidden = viewModel.isHidden(provider)

        HStack(alignment: .top, spacing: 8) {

            // Provider icon
            ZStack {
                providerIcon(for: provider)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            .frame(width: 26, height: 26)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isHidden ? 0.4 : (isConnected ? 1.0 : 0.3))

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isConnected && !isHidden ? .primary : .secondary)

                if isConnected {
                    Text(connection.statusText)
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if provider.hasAPI {
                    Text(connection.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Shared pool description for platform providers
                if let poolDesc = provider.sharedPoolDescription, !isConnected {
                    Text(poolDesc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Gemini plan selector when connected
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

            // Right-side controls — determined by provider state
            VStack(alignment: .trailing, spacing: 4) {
                if isConnected {
                    // State 2 & 3: Connected — show visibility toggle
                    Toggle("", isOn: visibilityBinding(for: provider))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()

                    // State 3: Hidden — show Disconnect button below toggle
                    if isHidden {
                        disconnectButton(for: provider)
                    }
                } else {
                    // State 1: Not connected
                    notConnectedControl(for: provider, connection: connection)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 0.5)
            }
        }
        .opacity(isHidden ? 0.7 : 1)
        .sheet(isPresented: $showingPATEntry) {
            patEntrySheet
        }
    }

    // MARK: - Not-Connected Control

    @ViewBuilder
    private func notConnectedControl(for provider: ProviderId, connection: ProviderConnectionState) -> some View {
        if !provider.hasAPI {
            Text("Coming Soon")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if provider.usesAPIKeyAuth {
            smallActionButton("Connect") { apiKeyEntryProvider = provider }
        } else if provider == .copilot {
            // Copilot has its own PAT sheet
            switch connection {
            case .notInstalled, .installedNoAuth:
                smallActionButton("Connect") { showingPATEntry = true }
                    .help("Enter a GitHub Personal Access Token")
            case .authExpired:
                smallActionButton("Reconnect") { showingPATEntry = true }
                    .help("Enter a new GitHub Personal Access Token")
            default:
                EmptyView()
            }
        } else {
            // CLI-based providers
            switch connection {
            case .notInstalled:
                smallActionButton("Install") { provider.openInstallInTerminal() }
                    .help("Opens Terminal to install \(provider.displayName)")
            case .installedNoAuth:
                smallActionButton("Sign In") { provider.openLoginInTerminal() }
                    .help("Opens Terminal to sign in")
            case .authExpired:
                smallActionButton("Fix") { provider.openLoginInTerminal() }
                    .help("Opens Terminal to reconnect")
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Disconnect Button

    @ViewBuilder
    private func disconnectButton(for provider: ProviderId) -> some View {
        // Only API-key providers and Copilot PAT are disconnectable.
        // CLI providers (Claude, Codex, Gemini, Cursor) auth via filesystem — no disconnect.
        if provider.usesAPIKeyAuth {
            smallActionButton("Disconnect") {
                APIKeyService.delete(for: provider)
                viewModel.redetectProviders()
            }
        } else if provider == .copilot {
            smallActionButton("Disconnect") {
                CopilotKeychainService.deletePAT()
                viewModel.redetectProviders()
            }
        }
    }

    // MARK: - Visibility Binding

    private func visibilityBinding(for provider: ProviderId) -> Binding<Bool> {
        Binding(
            get: { !viewModel.isHidden(provider) },
            set: { isVisible in
                if isVisible == viewModel.isHidden(provider) {
                    // Toggle: currently hidden and being shown, or currently shown and being hidden
                    viewModel.toggleVisibility(for: provider)
                }
            }
        )
    }

    // MARK: - Shared Helpers

    private func smallActionButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Icon Styling

    private func providerIcon(for provider: ProviderId) -> Image {
        let suffix = colorScheme == .dark ? "-white" : "-black"
        let name = "\(provider.iconBaseName)\(suffix)"
        if let nsImage = NSImage(named: name) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "sparkles")
    }

    // MARK: - PAT Entry Sheet (Copilot)

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
        .frame(width: 360)
    }

    // MARK: - API Key Entry Sheet (ElevenLabs, Runway, Stable Diffusion)

    private var apiKeyEntrySheet: some View {
        VStack(spacing: 16) {
            Text("Connect \(apiKeyEntryProvider?.displayName ?? "")")
                .font(.headline)

            Text("Enter your API key.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("API Key", text: $apiKeyText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            HStack {
                Spacer()

                Button("Cancel") {
                    apiKeyText = ""
                    apiKeyEntryProvider = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Connect") {
                    guard let provider = apiKeyEntryProvider else { return }
                    let trimmed = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    APIKeyService.save(trimmed, for: provider)
                    apiKeyText = ""
                    apiKeyEntryProvider = nil
                    viewModel.redetectProviders()
                    viewModel.refresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
