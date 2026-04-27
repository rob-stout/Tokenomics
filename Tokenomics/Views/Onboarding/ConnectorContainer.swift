import SwiftUI

/// Orchestrates the new onboarding flow: Welcome → Chooser → ConnectorView.
/// Owns the lifecycle of the active `ConnectorViewModel` and routes outcome
/// callbacks (Add another / I'm all set) back into the chooser or out to
/// onboarding completion.
struct ConnectorContainer: View {
    @ObservedObject var viewModel: UsageViewModel

    /// Called when the user finishes onboarding (either by tapping "I'm all set"
    /// after connecting or by skipping).
    var onComplete: () -> Void

    @State private var screen: Screen = .welcome
    @State private var activeConnector: ConnectorViewModel?

    enum Screen {
        case welcome
        case chooser
        case connector
    }

    var body: some View {
        Group {
            switch screen {
            case .welcome:
                WelcomeView(
                    onGetStarted: { screen = .chooser },
                    onSkip: completeOnboarding
                )
            case .chooser:
                ProviderChooserView(
                    viewModel: viewModel,
                    onPick: open(provider:),
                    onAllSet: completeOnboarding
                )
            case .connector:
                if let active = activeConnector {
                    ConnectorView(
                        viewModel: active,
                        onBack: { screen = .chooser }
                    )
                } else {
                    // Defensive — shouldn't be reachable.
                    Color.clear.onAppear { screen = .chooser }
                }
            }
        }
    }

    // MARK: - Navigation

    private func open(provider: ProviderId) {
        let connector = makeConnector(for: provider)
        activeConnector = ConnectorViewModel(
            connector: connector,
            onOutcome: { outcome in
                switch outcome {
                case .addAnother:
                    screen = .chooser
                    activeConnector = nil
                    viewModel.redetectProviders()
                case .allSet:
                    completeOnboarding()
                }
            }
        )
        screen = .connector
    }

    private func completeOnboarding() {
        viewModel.completeOnboarding()
        activeConnector = nil
        onComplete()
    }

    // MARK: - Connector factory

    private func makeConnector(for provider: ProviderId) -> any ProviderConnector {
        switch provider {
        case .cursor:
            return CursorConnector()
        case .copilot:
            return CopilotConnector(onRequestAuth: { [viewModel] in
                viewModel.copilotPATEntryRequested = true
            })
        case .claude:
            return ClaudeConnector()
        case .codex:
            return CodexConnector()
        case .gemini:
            return GeminiConnector()
        case .stableDiffusion:
            return APIKeyConnector(
                providerId: .stableDiffusion,
                provider: StableDiffusionProvider(),
                onRequestKey: { [viewModel] in viewModel.apiKeyEntryProvider = .stableDiffusion }
            )
        case .runway:
            return APIKeyConnector(
                providerId: .runway,
                provider: RunwayProvider(),
                onRequestKey: { [viewModel] in viewModel.apiKeyEntryProvider = .runway }
            )
        case .elevenlabs:
            return APIKeyConnector(
                providerId: .elevenlabs,
                provider: ElevenLabsProvider(),
                onRequestKey: { [viewModel] in viewModel.apiKeyEntryProvider = .elevenlabs }
            )
        case .midjourney, .suno, .udio:
            // Coming Soon — picker disables these rows. Defensive fallback.
            return ClaudeConnector()
        }
    }
}
