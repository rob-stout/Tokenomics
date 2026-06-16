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
    /// Back-navigation history. Every user-initiated forward step pushes the
    /// screen it left; Back pops one entry. This makes Back always return to the
    /// actual previous step regardless of which path reached the current screen
    /// (the chooser and connector are both reachable from multiple origins).
    @State private var history: [Screen] = []
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

    // MARK: Hub-and-spoke execution state
    //
    // "Your shortest path" (setupPlan) is the hub the user returns to between
    // steps; each step launches its connector (the spoke) and checks off on return.

    /// Step numbers completed so far — drives the SetupPlanStep checkboxes.
    @State private var completedStepNumbers: Set<Int> = []
    /// The plan step number whose connector is currently open (so its outcome
    /// checks the right box). nil when sitting on the hub.
    @State private var activeStepNumber: Int?
    /// True once "Start setup" has been tapped — flips the hub's primary button
    /// from "Start setup" to "Continue" / "Show my usage".
    @State private var hasStartedSetup = false

    // MARK: Screen transition

    /// Direction of the most recent navigation — drives the slide transition.
    /// Forward pushes the new screen in from the right; backward reverses it.
    @State private var navDirection: NavDirection = .forward

    enum NavDirection { case forward, backward }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Screen {
        case welcome
        case permissions
        case multiSelect
        case autoConnect
        case setupPlan
        case chooser
        case connector
    }

    var body: some View {
        Group {
            switch screen {
            case .welcome:
                WelcomeView(
                    onGetStarted: { go(to: .permissions) },
                    onSkip: completeOnboarding
                )
            case .permissions:
                PermissionsStep(
                    onContinue: { go(to: .multiSelect) },
                    onBack: { goBack() }
                )
                // Match chooser's winbody inset — mockup .winbody padding 32/40/28
                .padding(.top, Tokens.Spacing.s6)
                .padding(.horizontal, 40)
                .padding(.bottom, Tokens.Spacing.s5 + 4)
            case .multiSelect:
                MultiSelectStep(
                    selected: $draftSelection,
                    detectionAnnotations: detectionAnnotations,
                    onContinue: { proceedFromMultiSelect() },
                    onSetupOneAtATime: { go(to: .chooser) },
                    onBack: { goBack() }
                )
                .padding(.top, Tokens.Spacing.s6)
                .padding(.horizontal, 40)
                .padding(.bottom, Tokens.Spacing.s5 + 4)
                // Run detection once when this screen appears. Results pre-populate
                // draftSelection with detected brands and feed annotation labels.
                .task(id: "detection") {
                    await runDetection()
                }
            case .autoConnect:
                AutoConnectStep(
                    resolve: { await resolveAutoConnect() },
                    onFinished: { connected in handleAutoConnectFinished(connected) }
                )
                .padding(.top, Tokens.Spacing.s6)
                .padding(.horizontal, 40)
                .padding(.bottom, Tokens.Spacing.s5 + 4)
            case .setupPlan:
                SetupPlanStep(
                    plan: buildPlan(),
                    completedSteps: completedStepNumbers,
                    hasStarted: hasStartedSetup,
                    onStart: launchNextStep,
                    onBack: { goBack() }
                )
                .padding(.top, Tokens.Spacing.s6)
                .padding(.horizontal, 40)
                .padding(.bottom, Tokens.Spacing.s5 + 4)
            case .chooser:
                ProviderChooserView(
                    viewModel: viewModel,
                    onPick: open(provider:),
                    onAllSet: completeOnboarding,
                    // Back only when there's a real previous step (reached via
                    // "set them up one at a time"). As the entry root — opened from
                    // Settings with providers already connected — there's nothing to
                    // go back to, so hide it ("I'm all set" is the exit). At the root
                    // we offer "Start over" instead: re-run the guided wizard.
                    onBack: history.isEmpty ? nil : { goBack() },
                    onStartOver: history.isEmpty ? { startOver() } : nil
                )
                // Chooser winbody inset — matches mockup .winbody padding: 32px 40px 28px
                .padding(.top, Tokens.Spacing.s6)        // 32pt
                .padding(.horizontal, 40)                // 40pt — mockup literal
                .padding(.bottom, Tokens.Spacing.s5 + 4) // 28pt
            case .connector:
                if let active = activeConnector {
                    ConnectorView(
                        viewModel: active,
                        onBack: { goBack() }
                    )
                } else {
                    // Defensive — shouldn't be reachable.
                    Color.clear.onAppear { screen = .chooser }
                }
            }
        }
        // Directional slide between screens. `.id(screen)` gives each screen a
        // distinct identity so SwiftUI inserts/removes (and thus transitions) on
        // change; only changes wrapped in `withAnimation` (advance/retreat/go/
        // goBack) animate — the un-animated onAppear routing below stays an
        // instant cut. The shared bg sits OUTSIDE this so it never slides.
        .id(screen)
        .transition(navTransition)
        .background(Tokens.DynamicColor.bg.ignoresSafeArea())
        // Reset to chooser on re-entry so users who completed or cancelled a
        // previous flow don't land on a stale connector screen.
        .onAppear {
            // Pre-target takes priority: if a provider was queued, route there now.
            if let targetProvider = OnboardingTarget.shared.preselected {
                OnboardingTarget.shared.preselected = nil
                isPreTargeted = true
                history = []
                open(provider: targetProvider)
                return
            }

            if screen == .connector && activeConnector == nil {
                history = []
                screen = .chooser
            }
            // Returning users with at least one provider connected land on the
            // chooser hub (add more / I'm all set). But if nothing is connected
            // yet, keep them at the start of the guided flow (Welcome) rather than
            // dropping them on an empty hub.
            let firstLaunchScreens: [Screen] = [.welcome, .permissions, .multiSelect, .autoConnect, .setupPlan]
            if viewModel.hasCompletedOnboarding
                && !viewModel.connectedProviders.isEmpty
                && firstLaunchScreens.contains(screen) {
                history = []
                screen = .chooser
            }
        }
        // Also react when the window is already open and a pre-target arrives live.
        .onReceive(OnboardingTarget.shared.$preselected) { targetProvider in
            guard let targetProvider else { return }
            OnboardingTarget.shared.preselected = nil
            isPreTargeted = true
            history = []
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

    // MARK: - Auto-connect (already installed + signed in)

    /// CLI/desktop providers whose connection can be established with zero user
    /// interaction — `checkConnection()` reads local credentials (and validates
    /// them live). Everything else (extension install, API-key paste) needs the user.
    private func isAutoConnectableCLI(_ id: ProviderId) -> Bool {
        switch id {
        case .claude, .codex, .gemini, .copilot, .cursor: return true
        default: return false
        }
    }

    /// Leaving MultiSelect: if the plan has any CLI steps, route through the
    /// auto-connect explainer (it probes them and checks off the ready ones).
    /// If there are no CLI steps at all, there's nothing to auto-connect — go
    /// straight to the plan.
    private func proceedFromMultiSelect() {
        let plan = buildPlan()
        let hasCLISteps = plan.steps.contains { isAutoConnectableCLI($0.launchTarget) }
        go(to: hasCLISteps ? .autoConnect : .setupPlan)
    }

    /// Probes the plan's CLI steps for real, already-signed-in connections.
    /// Returns the connected providers in plan order plus whether any other work
    /// remains. Runs on-screen so any credential prompt fires while the user is
    /// looking at the "checking" UI.
    @MainActor
    private func resolveAutoConnect() async -> AutoConnectStep.Resolution {
        let plan = buildPlan()
        let candidates = plan.steps.map(\.launchTarget).filter(isAutoConnectableCLI)
        let connectedSet = await viewModel.probeAutoConnectable(candidates)
        let connected = plan.steps.map(\.launchTarget).filter { connectedSet.contains($0) }
        let remaining = plan.steps.contains { step in
            !completedStepNumbers.contains(step.number) && !connected.contains(step.launchTarget)
        }
        return AutoConnectStep.Resolution(connected: connected, hasRemaining: remaining)
    }

    /// The explainer finished: check off every auto-connected step. If that
    /// leaves nothing for the user, finish onboarding; otherwise land on the hub
    /// with the ready ones pre-checked — "here's what still needs you".
    @MainActor
    private func handleAutoConnectFinished(_ connected: [ProviderId]) {
        let result = Self.applyAutoConnect(
            plan: buildPlan(),
            alreadyCompleted: completedStepNumbers,
            connected: connected
        )
        completedStepNumbers = result.completed
        if result.allDone {
            completeOnboarding()
        } else {
            // Replace the transitional screen — Back from the hub returns to
            // MultiSelect (auto-connect is skipped in history), which is correct.
            advance(to: .setupPlan)
        }
    }

    /// Pure checkoff logic: marks each auto-connected provider's plan step done
    /// and reports whether the whole plan is now complete. A connected id with no
    /// matching step is ignored (it should never check off something not in the
    /// plan). Extracted for testing — this guards the "only genuinely-connected
    /// steps get checked" guarantee.
    static func applyAutoConnect(
        plan: SetupPlan,
        alreadyCompleted: Set<Int>,
        connected: [ProviderId]
    ) -> (completed: Set<Int>, allDone: Bool) {
        var completed = alreadyCompleted
        for id in connected {
            if let step = plan.steps.first(where: { $0.launchTarget == id }) {
                completed.insert(step.number)
            }
        }
        let allDone = !plan.steps.isEmpty && plan.steps.allSatisfy { completed.contains($0.number) }
        return (completed, allDone)
    }

    // MARK: - Synthesis Execution (hub-and-spoke)

    /// Called by the SetupPlanStep primary button. Launches the next not-yet-done
    /// step's connector, or finishes onboarding once every step is checked.
    ///
    /// The plan screen is the hub: each step launches its connector (the spoke),
    /// which returns here on completion with that step checked. Steps are NOT
    /// auto-chained — the user advances from the hub via "Continue".
    @MainActor
    private func launchNextStep() {
        hasStartedSetup = true
        let plan = buildPlan()
        guard let next = plan.steps.first(where: { !completedStepNumbers.contains($0.number) }) else {
            completeOnboarding()
            return
        }
        activeStepNumber = next.number
        // Record the hub so Back from the connector returns here (un-checked).
        history.append(.setupPlan)
        openSynthesis(provider: next.launchTarget)
    }

    /// Opens a step's connector. On completion it returns to the hub (the plan
    /// checklist) with that step checked — it does NOT auto-chain to the next
    /// connector; the user advances from the hub.
    private func openSynthesis(provider: ProviderId) {
        let connector = makeConnector(for: provider)
        activeConnector = ConnectorViewModel(
            connector: connector,
            onOutcome: { [self] outcome in
                switch outcome {
                case .addAnother, .skipped:
                    // Mark this step handled and return to the hub checklist.
                    if let n = activeStepNumber { completedStepNumbers.insert(n) }
                    activeStepNumber = nil
                    activeConnector = nil
                    viewModel.redetectProviders()
                    _ = history.popLast()  // remove the .setupPlan pushed on launch
                    // Pop back to the hub — the spoke slides out to the right.
                    retreat(to: .setupPlan)
                case .allSet:
                    completeOnboarding()
                }
            }
        )
        // Push the spoke in from the right.
        advance(to: .connector)
    }

    // MARK: - Navigation

    private static let navAnimation: Animation = .easeInOut(duration: 0.26)

    /// The slide transition for the current `navDirection`. Forward enters from
    /// the right (old exits left); backward reverses. Reduce Motion falls back to
    /// a crossfade — a horizontal slide is exactly the kind of motion it guards against.
    private var navTransition: AnyTransition {
        if reduceMotion { return .opacity }
        switch navDirection {
        case .forward:
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .backward:
            return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }

    /// Animate forward (push): new screen slides in from the right.
    private func advance(to next: Screen) {
        navDirection = .forward
        withAnimation(Self.navAnimation) { screen = next }
    }

    /// Animate backward (pop): previous screen slides in from the left.
    private func retreat(to previous: Screen) {
        navDirection = .backward
        withAnimation(Self.navAnimation) { screen = previous }
    }

    /// Push the current screen onto the back-history and navigate forward.
    private func go(to next: Screen) {
        history.append(screen)
        advance(to: next)
    }

    /// Pop one step off the back-history. If there's nothing to return to
    /// (e.g. a pre-targeted reconnect that opened straight into a connector),
    /// close the onboarding window instead of stranding the user.
    private func goBack() {
        if let previous = history.popLast() {
            retreat(to: previous)
        } else {
            completeOnboarding()
        }
    }

    private func open(provider: ProviderId) {
        // Record where we came from so Back returns there. Pre-targeted sessions
        // open directly into a connector with no in-app origin, so they don't.
        if !isPreTargeted {
            history.append(screen)
        }
        let connector = makeConnector(for: provider)
        activeConnector = ConnectorViewModel(
            connector: connector,
            // Label the success CTA for where `.addAnother` actually lands: the
            // chooser ("Add a provider") returns to add more; a pre-targeted
            // session just finishes and shows usage.
            continueLabel: isPreTargeted ? "Show my usage" : "Add another provider",
            onOutcome: { [self] outcome in
                switch outcome {
                case .addAnother:
                    if isPreTargeted {
                        // Pre-targeted sessions have no chooser context — treat as done.
                        completeOnboarding()
                    } else {
                        activeConnector = nil
                        viewModel.redetectProviders()
                        // Return to the chooser we pushed on entry (history stays balanced).
                        goBack()
                    }
                case .allSet:
                    completeOnboarding()
                case .skipped:
                    // Treat a skipped step the same as "all set" from the chooser path.
                    completeOnboarding()
                }
            }
        )
        advance(to: .connector)
    }

    /// Re-runs the guided wizard from the beginning. Clears the back-history and
    /// any draft synthesis state so detection re-seeds fresh, then lands on Welcome.
    private func startOver() {
        history = []
        draftSelection = []
        completedStepNumbers = []
        activeStepNumber = nil
        hasStartedSetup = false
        // Rewind to the very start — slide back to Welcome.
        retreat(to: .welcome)
    }

    private func completeOnboarding() {
        viewModel.completeOnboarding()
        activeConnector = nil
        isPreTargeted = false
        completedStepNumbers = []
        activeStepNumber = nil
        hasStartedSetup = false
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
        case .chatgpt:
            // In the synthesis flow .chatgpt is the BrowserExtensionConnector's id.
            // In the chooser path this case was previously a defensive fallback —
            // now it correctly routes to the extension install step.
            return BrowserExtensionConnector(webCompanion: webCompanion)
        case .geminiConsumer:
            // Extension-fed pool — data arrives via the gemini-watch content script
            // over the NMH bridge. No standalone connector; route through the
            // BrowserExtensionConnector just like ChatGPT/Midjourney.
            return BrowserExtensionConnector(webCompanion: webCompanion)
        case .midjourney, .grok, .perplexity, .leonardo, .elevenlabs, .suno, .udio:
            // These are web-companion-only with no standalone connector yet —
            // their usage arrives over the NMH bridge from the extension readers.
            // ElevenLabs used to route to APIKeyConnector, but it's bridge-fed now
            // (Firebase bearer auth, usesAPIKeyAuth == false), so it belongs here.
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
        .stableDiffusion, .midjourney, .leonardo, .runway, .elevenlabs,
        .grok, .perplexity
    ]
}
