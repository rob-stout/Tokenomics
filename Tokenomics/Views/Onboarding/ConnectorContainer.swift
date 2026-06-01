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

    /// WebCompanionService instance for BrowserExtensionConnector.
    /// Passed in from the app root so it shares the same singleton the rest of
    /// the app uses (FSEvents watch is already running on it).
    var webCompanion: any WebCompanionStateProvider

    /// Called when the user finishes onboarding (either by tapping "I'm all set"
    /// after connecting or by skipping).
    var onComplete: () -> Void

    @State private var screen: Screen = .welcome
    @State private var activeConnector: ConnectorViewModel?
    /// True when the current session was started via a pre-targeted provider link
    /// (Install / Sign In / Reconnect from Settings or popover). Used to treat
    /// "Add another" as "close window" rather than routing back to chooser.
    @State private var isPreTargeted = false

    // MARK: - Synthesis flow state

    /// Brand-level selection from MultiSelectStep. Starts empty; pre-populated
    /// with detected brands once DetectionService runs on entering multiSelect.
    @State private var draftSelection: Set<ProviderId> = []

    /// Latest detection results — populated by DetectionService on the multiSelect
    /// screen and kept alive for PlanBuilder (which needs them on the setupPlan screen).
    @State private var detectionResults: [BrandId: BrandDetection] = [:]

    /// Per-ProviderId annotation strings derived from detectionResults. Consumed
    /// by MultiSelectStep to show "already detected" sub-labels under each row.
    @State private var detectionAnnotations: [ProviderId: String] = [:]

    /// Ordered queue of providers to execute in the synthesis path. Built from
    /// the plan just before execution starts; `.chatgpt` represents the
    /// BrowserExtensionConnector step (covers all web-companion providers).
    @State private var synthesisQueue: [ProviderId] = []

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
                    detectionAnnotations: detectionAnnotations,
                    onContinue: { screen = .setupPlan },
                    onSetupOneAtATime: { screen = .chooser },
                    onBack: { screen = .permissions }
                )
                .padding(.top, Tokens.Spacing.s6)
                .padding(.horizontal, 40)
                .padding(.bottom, Tokens.Spacing.s5 + 4)
                // Run detection once when this screen appears. Results pre-populate
                // draftSelection with detected brands and feed annotation labels.
                .task(id: "detection") {
                    await runDetection()
                }
            case .setupPlan:
                SetupPlanStep(
                    plan: buildPlan(),
                    onStart: startSynthesisExecution,
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

    // MARK: - Detection

    /// Runs DetectionService concurrently, updates annotation state, and
    /// pre-populates draftSelection with detected brands. Only overwrites
    /// draftSelection on first detection (while it is still empty) so that
    /// users who tapped Back and returned to multiSelect keep their edits.
    @MainActor
    private func runDetection() async {
        let service = DetectionService()
        let results = await service.detect()
        detectionResults = results
        detectionAnnotations = results.providerAnnotations

        // Seed the selection with detected brands only on first entry — once the
        // user has made manual edits we don't want to overwrite their choices.
        if draftSelection.isEmpty {
            let detectedProviderIds = results.values
                .filter(\.isDetected)
                .flatMap { detection in detection.brand.pools }
            draftSelection = Set(detectedProviderIds).intersection(
                Set(MultiSelectStep.selectableProviderIds)
            )
        }
    }

    // MARK: - Plan

    /// Builds a SetupPlan from the current draft selection and latest detection
    /// results. Called inline by the setupPlan case — always reflects current state.
    private func buildPlan() -> SetupPlan {
        let brandSelection = Set(draftSelection.map(\.brand))
        return PlanBuilder.build(selection: brandSelection, detection: detectionResults)
    }

    // MARK: - Synthesis Execution

    /// Called by SetupPlanStep's "Start setup" button. Converts the current
    /// selection into an ordered execution queue and kicks off the first step.
    ///
    /// Queue ordering mirrors PlanBuilder's step ordering:
    ///   1. BrowserExtensionConnector (covers all web-companion providers in one step)
    ///   2. CLI/desktop providers, brand-alphabetical
    ///   3. API-key providers, brand-alphabetical
    ///
    /// `.chatgpt` is used as the queue entry for the extension step because
    /// BrowserExtensionConnector declares that as its `id`.
    @MainActor
    private func startSynthesisExecution() {
        let brandSelection = Set(draftSelection.map(\.brand))
        synthesisQueue = buildExecutionQueue(from: brandSelection)
        advanceSynthesisQueue()
    }

    /// Pops the next provider from `synthesisQueue` and opens it, or finishes
    /// onboarding if the queue is empty.
    @MainActor
    private func advanceSynthesisQueue() {
        guard !synthesisQueue.isEmpty else {
            completeOnboarding()
            return
        }
        let next = synthesisQueue.removeFirst()
        openSynthesis(provider: next)
    }

    /// Opens a connector in synthesis mode. Outcomes advance the queue rather
    /// than routing to the chooser — the queue owns the sequencing here.
    private func openSynthesis(provider: ProviderId) {
        let connector = makeConnector(for: provider)
        activeConnector = ConnectorViewModel(
            connector: connector,
            onOutcome: { [self] outcome in
                switch outcome {
                case .addAnother, .skipped:
                    // In synthesis mode both "add another" and "skip" advance
                    // to the next queued provider rather than dropping to chooser.
                    screen = .connector  // keep showing ConnectorView chrome while VM swaps
                    activeConnector = nil
                    viewModel.redetectProviders()
                    advanceSynthesisQueue()
                case .allSet:
                    completeOnboarding()
                }
            }
        )
        screen = .connector
    }

    /// Builds an ordered list of ProviderIds to execute for the given brand set.
    ///
    /// Extension-only providers collapse into a single `.chatgpt` entry
    /// (BrowserExtensionConnector's id) because the extension covers all of
    /// them in one install step. CLI and API-key providers each get one entry.
    private func buildExecutionQueue(from brandSelection: Set<BrandId>) -> [ProviderId] {
        var queue: [ProviderId] = []

        // Extension step: one BrowserExtensionConnector run if any selected brand
        // has a web-companion-only pool member (ChatGPT, Midjourney, etc.).
        let hasWebCompanionProviders = brandSelection.contains { brand in
            brand.pools.contains(where: isWebCompanionOnly)
        }
        if hasWebCompanionProviders {
            queue.append(.chatgpt)
        }

        // CLI/desktop and API-key providers — one per provider ID, brand-alphabetical.
        let sortedBrands = brandSelection.sorted { $0.rawValue < $1.rawValue }
        for brand in sortedBrands {
            let cliProviders = brand.pools
                .filter { !isWebCompanionOnly($0) }
                .sorted { $0.rawValue < $1.rawValue }
            queue.append(contentsOf: cliProviders)
        }

        return queue
    }

    /// True when a ProviderId is only reachable via the browser extension — no
    /// CLI tool and no local credentials path. Mirrors the same classification
    /// in PlanBuilder (kept local to avoid exposing PlanBuilder internals).
    private func isWebCompanionOnly(_ provider: ProviderId) -> Bool {
        switch provider {
        case .chatgpt, .midjourney, .suno, .udio:
            return true
        default:
            return false
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
                    // Treat a skipped step the same as "all set" from the chooser path.
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
        synthesisQueue = []
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
        case .chatgpt:
            // In the synthesis flow .chatgpt is the BrowserExtensionConnector's id.
            // In the chooser path this case was previously a defensive fallback —
            // now it correctly routes to the extension install step.
            return BrowserExtensionConnector(webCompanion: webCompanion)
        case .midjourney, .suno, .udio:
            // These are web-companion-only with no standalone connector yet.
            // BrowserExtensionConnector covers them as part of the extension batch;
            // reaching this path individually would be a routing bug. Defensive fallback.
            return BrowserExtensionConnector(webCompanion: webCompanion)
        }
    }
}

// MARK: - MultiSelectStep selectable provider IDs

extension MultiSelectStep {
    /// The full set of ProviderId values that appear as rows in MultiSelectStep.
    /// Used by ConnectorContainer to filter detection results to only the providers
    /// the user can actually interact with in the multi-select screen.
    static let selectableProviderIds: Set<ProviderId> = [
        .claude, .chatgpt, .gemini,
        .copilot, .cursor,
        .stableDiffusion, .midjourney, .runway, .elevenlabs
    ]
}
