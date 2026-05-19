import SwiftUI

/// Orchestrates the new onboarding flow: Welcome → Chooser → ConnectorView.
/// Owns the lifecycle of the active `ConnectorViewModel` and routes outcome
/// callbacks (Add another / I'm all set) back into the chooser or out to
/// onboarding completion.
///
/// When `OnboardingTarget.shared.preselected` is set before the window opens,
/// the container skips Welcome and Chooser and lands directly on that provider's
/// connector flow. Both "Add another" and "I'm all set" outcomes close the window
/// in that case, since the chooser context doesn't apply.
struct ConnectorContainer: View {
    @ObservedObject var viewModel: UsageViewModel

    /// Called when the user finishes onboarding (either by tapping "I'm all set"
    /// after connecting or by skipping).
    var onComplete: () -> Void

    @State private var screen: Screen = .welcome
    @State private var activeConnector: ConnectorViewModel?
    /// True when the current session was started via a pre-targeted provider link
    /// (Install / Sign In / Reconnect from Settings or popover). Used to treat
    /// "Add another" as "close window" rather than routing back to chooser.
    @State private var isPreTargeted = false

    // MARK: - Phase 3 (smart synthesis) draft state — stub data
    //
    // The multi-select and setup-plan screens currently run on hardcoded
    // detection annotations + a stubbed plan so the visual flow can be
    // reviewed end-to-end against the Figma board. Real detection + plan
    // generation land in follow-up tasks; until then "Start setup" on the
    // plan screen falls back to the existing chooser.
    @State private var draftSelection: Set<ProviderId> = [.claude, .chatgpt, .cursor]

    private let stubDetectionAnnotations: [ProviderId: String] = [
        .claude: "Claude Code CLI · signed in at claude.ai",
        .chatgpt: "ChatGPT.app installed",
        .cursor: "Cursor.app installed"
    ]

    private var stubSetupPlan: SetupPlan {
        SetupPlan(
            providerCount: max(draftSelection.count, 1),
            stepCount: 3,
            estimatedDuration: "about a minute",
            steps: [
                .init(
                    number: 1,
                    title: "Install the Tokenomics browser extension",
                    description: "Covers 2 of the tools you picked at once:",
                    timeEstimate: "~1 min",
                    covers: ["Claude (via claude.ai)", "ChatGPT (via chat.openai.com)"]
                ),
                .init(
                    number: 2,
                    title: "Confirm Claude Code is connected",
                    description: "Already installed on your Mac — we just need to read your credentials.",
                    timeEstimate: "~5 sec",
                    covers: nil
                ),
                .init(
                    number: 3,
                    title: "Confirm Cursor is connected",
                    description: "Already installed on your Mac — we just need to read your local data.",
                    timeEstimate: "~5 sec",
                    covers: nil
                ),
            ]
        )
    }

    @Environment(\.colorScheme) private var scheme

    enum Screen {
        case welcome
        case permissions
        case multiSelect
        case setupPlan
        case chooser
        case connector
    }

    var body: some View {
        Group {
            switch screen {
            case .welcome:
                WelcomeView(
                    onGetStarted: { screen = .permissions },
                    onSkip: completeOnboarding
                )
            case .permissions:
                PermissionsStep(
                    onContinue: { screen = .multiSelect },
                    onBack: { screen = .welcome }
                )
                // Match chooser's winbody inset — mockup .winbody padding 32/40/28
                .padding(.top, Tokens.Spacing.s6)
                .padding(.horizontal, 40)
                .padding(.bottom, Tokens.Spacing.s5 + 4)
            case .multiSelect:
                MultiSelectStep(
                    selected: $draftSelection,
                    detectionAnnotations: stubDetectionAnnotations,
                    onContinue: { screen = .setupPlan },
                    onSetupOneAtATime: { screen = .chooser },
                    onBack: { screen = .permissions }
                )
                .padding(.top, Tokens.Spacing.s6)
                .padding(.horizontal, 40)
                .padding(.bottom, Tokens.Spacing.s5 + 4)
            case .setupPlan:
                SetupPlanStep(
                    plan: stubSetupPlan,
                    // Placeholder: real batched execution lands in a follow-up
                    // task. For now, "Start setup" hands off to the existing
                    // chooser so the rest of the flow stays clickable.
                    onStart: { screen = .chooser },
                    onBack: { screen = .multiSelect }
                )
                .padding(.top, Tokens.Spacing.s6)
                .padding(.horizontal, 40)
                .padding(.bottom, Tokens.Spacing.s5 + 4)
            case .chooser:
                ProviderChooserView(
                    viewModel: viewModel,
                    onPick: open(provider:),
                    onAllSet: completeOnboarding,
                    onBack: { screen = .welcome }
                )
                // Chooser winbody inset — matches mockup .winbody padding: 32px 40px 28px
                .padding(.top, Tokens.Spacing.s6)        // 32pt
                .padding(.horizontal, 40)                // 40pt — mockup literal
                .padding(.bottom, Tokens.Spacing.s5 + 4) // 28pt
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
        .background(Tokens.DynamicColor.bg.ignoresSafeArea())
        // Reset to chooser on re-entry so users who completed or cancelled a
        // previous flow don't land on a stale connector screen.
        .onAppear {
            // Pre-target takes priority: if a provider was queued, route there now.
            if let targetProvider = OnboardingTarget.shared.preselected {
                OnboardingTarget.shared.preselected = nil
                isPreTargeted = true
                open(provider: targetProvider)
                return
            }

            if screen == .connector && activeConnector == nil {
                screen = .chooser
            }
            // If the user previously finished onboarding but re-opened via Settings,
            // land on the chooser instead of welcome/permissions/synthesis so they
            // can add more providers without re-running the first-launch chrome.
            let firstLaunchScreens: [Screen] = [.welcome, .permissions, .multiSelect, .setupPlan]
            if viewModel.hasCompletedOnboarding && firstLaunchScreens.contains(screen) {
                screen = .chooser
            }
        }
        // Also react when the window is already open and a pre-target arrives live.
        .onReceive(OnboardingTarget.shared.$preselected) { targetProvider in
            guard let targetProvider else { return }
            OnboardingTarget.shared.preselected = nil
            isPreTargeted = true
            open(provider: targetProvider)
        }
    }

    // MARK: - Navigation

    private func open(provider: ProviderId) {
        let connector = makeConnector(for: provider)
        activeConnector = ConnectorViewModel(
            connector: connector,
            onOutcome: { [self] outcome in
                switch outcome {
                case .addAnother:
                    if isPreTargeted {
                        // Pre-targeted sessions have no chooser context — treat as done.
                        completeOnboarding()
                    } else {
                        screen = .chooser
                        activeConnector = nil
                        viewModel.redetectProviders()
                    }
                case .allSet:
                    completeOnboarding()
                case .skipped:
                    // Treat a skipped step the same as "all set" for now.
                    // The Phase 5.5 orchestrator will route this differently
                    // when BrowserExtensionConnector is wired into the synthesis flow.
                    completeOnboarding()
                }
            }
        )
        screen = .connector
    }

    private func completeOnboarding() {
        viewModel.completeOnboarding()
        activeConnector = nil
        isPreTargeted = false
        onComplete()
    }

    // MARK: - Connector factory

    private func makeConnector(for provider: ProviderId) -> any ProviderConnector {
        switch provider {
        case .cursor:
            return CursorConnector()
        case .copilot:
            // Guided window: no PAT callback — flow uses gh auth login.
            return CopilotConnector()
        case .claude:
            return ClaudeConnector()
        case .codex:
            return CodexConnector()
        case .gemini:
            return GeminiConnector()
        case .stableDiffusion:
            return APIKeyConnector(
                providerId: .stableDiffusion,
                provider: StableDiffusionProvider()
            )
        case .runway:
            return APIKeyConnector(
                providerId: .runway,
                provider: RunwayProvider()
            )
        case .elevenlabs:
            return APIKeyConnector(
                providerId: .elevenlabs,
                provider: ElevenLabsProvider()
            )
        case .chatgpt, .midjourney, .suno, .udio:
            // Coming Soon / browser-session providers — picker disables these rows. Defensive fallback.
            return ClaudeConnector()
        }
    }
}
