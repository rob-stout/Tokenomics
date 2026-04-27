import SwiftUI

/// "Pick a provider" screen — flat list of all providers grouped by category,
/// each row tagged with a Quick / Guided badge. Connected providers show a
/// green checkmark but remain tappable for re-connect.
///
/// Mirrors the structure of AIConnectionsView so the user sees the same
/// chrome whether they're onboarding or revisiting from Settings.
struct ProviderChooserView: View {
    @ObservedObject var viewModel: UsageViewModel
    var onPick: (ProviderId) -> Void
    var onAllSet: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ProviderId.ProviderCategory.allCases, id: \.self) { category in
                        let providers = ProviderId.allCases.filter { $0.category == category }
                        if !providers.isEmpty {
                            sectionHeader(category.rawValue)
                            VStack(spacing: 0) {
                                ForEach(providers, id: \.self) { provider in
                                    providerRow(provider)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }

                    legendHint
                        .padding(.top, 4)

                    Button("I'm all set — show my usage") {
                        onAllSet()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Reserve space for symmetry; no back button on this screen
            // (it's the second-step of onboarding; "I'm all set" is the escape).
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text(" ")
            }
            .scaledFont(.caption)
            .hidden()

            Spacer()

            Text("Add a provider")
                .scaledFont(.headline)
                .fontWeight(.medium)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text(" ")
            }
            .scaledFont(.caption)
            .hidden()
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .scaledFont(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Row

    @ViewBuilder
    private func providerRow(_ provider: ProviderId) -> some View {
        let state = viewModel.providerStates[provider]
        let isConnected = state?.connection.isConnected ?? false
        let isAvailable = provider.hasAPI

        Button { onPick(provider) } label: {
            HStack(alignment: .top, spacing: 8) {
                ProviderIcon(provider: provider, isConnected: isConnected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .scaledFont(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isConnected ? .primary : (isAvailable ? .primary : .secondary))

                    if isConnected {
                        Text("Connected")
                            .scaledFont(.caption2)
                            .foregroundStyle(.green)
                    } else if isAvailable {
                        Text(statusText(for: provider))
                            .scaledFont(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let pool = provider.sharedPoolDescription, !isConnected {
                        Text(pool)
                            .scaledFont(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                badge(for: provider, isConnected: isConnected)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable && !isConnected)
    }

    private func statusText(for provider: ProviderId) -> String {
        let mode = connectorMode(for: provider)
        switch mode {
        case .quick: return "Quick setup"
        case .guided: return "Guided setup"
        }
    }

    @ViewBuilder
    private func badge(for provider: ProviderId, isConnected: Bool) -> some View {
        if isConnected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .scaledFont(.caption)
        } else if !provider.hasAPI {
            Text("Coming Soon")
                .scaledFont(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            Image(systemName: "chevron.right")
                .scaledFont(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Legend

    private var legendHint: some View {
        Text("**Quick** — sign in once, you're done.  **Guided** — Tokenomics walks you through. No Terminal, no command line.")
            .scaledFont(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Per-provider mode

    /// Which connector mode each provider uses. Single source of truth here so
    /// the chooser badge and the connector implementation stay in sync.
    private func connectorMode(for provider: ProviderId) -> ConnectorMode {
        switch provider {
        case .cursor, .copilot, .claude,
             .stableDiffusion, .runway, .elevenlabs:
            return .quick
        case .codex, .gemini:
            return .guided
        case .midjourney, .suno, .udio:
            return .quick   // unused — these rows are gated by hasAPI=false above
        }
    }
}
