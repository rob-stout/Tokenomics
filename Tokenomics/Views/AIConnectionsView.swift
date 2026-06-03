import SwiftUI

/// Settings sub-screen showing all providers grouped by category with connect/disconnect controls.
///
/// Connect / Re-connect / Sign In taps for CLI-based providers (Claude, Codex, Gemini, Cursor)
/// open the guided onboarding window pre-routed to that provider, so users get the full
/// step-by-step flow without ever seeing a Terminal window.
struct AIConnectionsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var geminiPlan: GeminiPlan = SettingsService.geminiPlan ?? .free
    @State private var patText = ""
    @State private var apiKeyText = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tokenomicsTextSize) private var textSize
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            helpBanner

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ProviderId.ProviderCategory.allCases, id: \.self) { category in
                        let brandsInCategory = BrandId.allCases.filter { $0.category == category }
                        if !brandsInCategory.isEmpty {
                            sectionHeader(category.rawValue)
                            VStack(spacing: 0) {
                                ForEach(brandsInCategory, id: \.self) { brand in
                                    brandGroup(for: brand, isLast: brand == brandsInCategory.last)
                                }
                            }
                            .padding(.bottom, 12)
                        }
                    }

                    // Hint text
                    Text("Toggle to show or hide providers. Reorder in the main view.")
                        .scaledFont(.caption2)
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
        .sheet(item: $viewModel.apiKeyEntryProvider) { _ in
            apiKeyEntrySheet
        }
    }

    // MARK: - Help Banner

    /// Quiet recovery affordance for users who land on Connections looking
    /// to add a provider but want the guided walk-through. Sits above the
    /// scroll so it stays visible regardless of list length.
    ///
    /// mockup .popover-help (lines 703–712):
    ///   bg accent@8%, border-bottom 1px border, padding 11×16, 12.5px, text-muted link
    private var helpBanner: some View {
        HStack(spacing: Tokens.Spacing.s1 + 2) { // 6pt
            Text("Need help connecting a provider?")
                .font(Tokens.Typography.App.caption)
                .foregroundStyle(Tokens.Color.textMuted(colorScheme))

            Spacer()

            Button {
                openWindow(id: "onboarding")
            } label: {
                Text("Open the guided setup →")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Tokens.Color.brand600)  // always brand-600 (accent is fine too; brand-600 matches mockup .text-link color)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Tokens.Spacing.s4) // 16pt — mockup padding: 11px 16px
        .padding(.vertical, 11)                   // 11pt — mockup padding-vertical: 11px
        .background(Tokens.Color.brand600.opacity(0.08)) // mockup: accent@8%
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Tokens.Color.border(colorScheme))
                .frame(height: 1)
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
                .scaledFont(.caption)
                .padding(.vertical, 4)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Text("Providers")
                .scaledFont(.headline)
                .fontWeight(.medium)

            Spacer()

            // Invisible balance for centering
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Settings")
            }
            .scaledFont(.caption)
            .hidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .scaledFont(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Brand Group

    /// Renders one brand. Single-pool brands (Claude, Cursor, …) are a flat
    /// connection row. Multi-pool brands (OpenAI, Google) get a non-interactive
    /// brand header followed by one indented sub-row per pool — each pool keeps
    /// its own status, meter, and visibility toggle, because the pools are
    /// separate meters (OpenAI: chat vs agentic/Codex; Google: web vs CLI).
    @ViewBuilder
    private func brandGroup(for brand: BrandId, isLast: Bool) -> some View {
        if brand.isMultiPool {
            brandHeader(for: brand)
            let orderedPools = brand.orderedPools
            ForEach(Array(orderedPools.enumerated()), id: \.element) { index, pool in
                connectionRow(
                    for: pool,
                    isLast: isLast && index == orderedPools.count - 1,
                    labelOverride: pool.poolLabel,
                    indented: true
                )
            }
        } else {
            connectionRow(for: brand.primaryPool, isLast: isLast)
        }
    }

    /// Non-interactive header introducing a multi-pool brand (the company as
    /// the platform). Visibility/connection live on the sub-rows below it.
    private func brandHeader(for brand: BrandId) -> some View {
        HStack(spacing: 8) {
            providerIcon(for: brand.primaryPool)
                .resizable()
                .scaledToFit()
                .frame(width: 16 * textSize.iconScale, height: 16 * textSize.iconScale)
                .frame(width: 26 * textSize.iconScale, height: 26 * textSize.iconScale)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(brand.companyAttribution ?? brand.displayName)
                .scaledFont(.caption)
                .fontWeight(.semibold)

            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Connection Row

    @ViewBuilder
    private func connectionRow(
        for provider: ProviderId,
        isLast: Bool = false,
        labelOverride: String? = nil,
        indented: Bool = false
    ) -> some View {
        let state = viewModel.providerStates[provider]
        let connection = state?.connection ?? .notInstalled
        let isConnected = connection.isConnected
        let isHidden = viewModel.isHidden(provider)

        HStack(alignment: .top, spacing: 8) {

            // Provider icon. Nested sub-pool rows show the surface glyph
            // (extension vs CLI) instead of the brand mark — the brand lives on
            // the group header above, so the glyph is what distinguishes the pools.
            ZStack {
                if indented, let symbol = provider.surfaceSymbol {
                    // Glyph sized to 90% of the brand-mark footprint so it reads as
                    // a sub-pool badge, not a competing logo. Box stays 26pt.
                    Image(systemName: symbol)
                        .font(.system(size: 13 * textSize.iconScale, weight: .regular))
                        .foregroundStyle(.primary)
                } else {
                    providerIcon(for: provider)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16 * textSize.iconScale, height: 16 * textSize.iconScale)
                }
            }
            .frame(width: 26 * textSize.iconScale, height: 26 * textSize.iconScale)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isHidden ? 0.4 : (isConnected ? 1.0 : 0.3))

            VStack(alignment: .leading, spacing: 2) {
                Text(labelOverride ?? provider.poolLabel)
                    .scaledFont(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isConnected && !isHidden ? .primary : .secondary)

                if isConnected {
                    Text(connection.statusText)
                        .scaledFont(.caption2)
                        .foregroundStyle(.green)
                } else if provider.hasAPI {
                    Text(connection.statusText)
                        .scaledFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let scope = provider.scopeDescription, scope != labelOverride {
                    Text(scope)
                        .scaledFont(.caption2)
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
                                    .scaledFont(.caption2)
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
        .padding(.leading, indented ? 22 : 0)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 0.5)
            }
        }
        .opacity(isHidden ? 0.7 : 1)
        .sheet(isPresented: $viewModel.copilotPATEntryRequested) {
            patEntrySheet
        }
    }

    // MARK: - Not-Connected Control

    @ViewBuilder
    private func notConnectedControl(for provider: ProviderId, connection: ProviderConnectionState) -> some View {
        if !provider.hasAPI {
            Text("Coming Soon")
                .scaledFont(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            // All connectable providers open the guided onboarding window pre-routed
            // to that provider's flow (CLI, API key, and OAuth alike).
            switch connection {
            case .notInstalled:
                smallActionButton("Connect") {
                    OnboardingTarget.shared.preselected = provider
                    openWindow(id: "onboarding")
                }
            case .installedNoAuth:
                smallActionButton("Sign In") {
                    OnboardingTarget.shared.preselected = provider
                    openWindow(id: "onboarding")
                }
            case .authExpired:
                smallActionButton("Reconnect") {
                    OnboardingTarget.shared.preselected = provider
                    openWindow(id: "onboarding")
                }
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
                .scaledFont(.caption2)
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
                .scaledFont(.headline)

            Text("Enter a fine-grained Personal Access Token with **Plan (read)** permission.")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("ghp_...", text: $patText)
                .textFieldStyle(.roundedBorder)
                .scaledFont(.caption)

            HStack {
                Button("Create Token") {
                    if let url = URL(string: "https://github.com/settings/personal-access-tokens/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    patText = ""
                    viewModel.copilotPATEntryRequested = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Connect") {
                    let trimmed = patText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    CopilotKeychainService.savePAT(trimmed)
                    patText = ""
                    viewModel.copilotPATEntryRequested = false
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
            Text("Connect \(viewModel.apiKeyEntryProvider?.displayName ?? "")")
                .scaledFont(.headline)

            Text("Enter your API key.")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)

            SecureField("API Key", text: $apiKeyText)
                .textFieldStyle(.roundedBorder)
                .scaledFont(.caption)

            HStack {
                Spacer()

                Button("Cancel") {
                    apiKeyText = ""
                    viewModel.apiKeyEntryProvider = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Connect") {
                    guard let provider = viewModel.apiKeyEntryProvider else { return }
                    let trimmed = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    APIKeyService.save(trimmed, for: provider)
                    apiKeyText = ""
                    viewModel.apiKeyEntryProvider = nil
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
