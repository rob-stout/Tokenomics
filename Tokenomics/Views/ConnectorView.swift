import SwiftUI

/// Universal connector view — handles every provider's "from zero to connected"
/// flow with consistent chrome. Routes between step types based on `step` enum.
struct ConnectorView: View {
    @ObservedObject var viewModel: ConnectorViewModel
    var onBack: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            // Titlebar-style header
            header
                .padding(.horizontal, Tokens.Spacing.s4)
                .padding(.top, Tokens.Spacing.s3)
                .padding(.bottom, Tokens.Spacing.s2)

            // 4-segment step indicator — hidden on states that don't warrant it.
            if !viewModel.stepperItems.isEmpty {
                OnboardingStepper(items: viewModel.stepperItems)
                    .padding(.horizontal, Tokens.Spacing.s4)
                    .padding(.top, Tokens.Spacing.s2)
                    .padding(.bottom, Tokens.Spacing.s2)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: Tokens.Motion.standard), value: viewModel.stepperItems)
            }

            ScrollView {
                content
                    // winbody inset — mockup .winbody: padding 32px 40px 28px
                    .padding(.top, Tokens.Spacing.s6)        // 32pt
                    .padding(.horizontal, 40)                // 40pt — mockup literal
                    .padding(.bottom, Tokens.Spacing.s5 + 4) // 28pt
            }
        }
        .background(Tokens.DynamicColor.bg.ignoresSafeArea())
        .navigationTitle("Connect \(viewModel.providerName)")
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Header

    /// Centered provider name with optional Back button (left) + invisible balance (right).
    /// The back button is hidden on screens that own their own footer back link
    /// (currently DetectStep) — avoids duplicate affordances.
    @ViewBuilder
    private var header: some View {
        let backInHeader = onBack != nil && !stepHasOwnBack
        HStack {
            if backInHeader, let onBack {
                Button(action: onBack) {
                    HStack(spacing: Tokens.Spacing.s1) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(Tokens.Typography.Onboarding.small.weight(.medium))
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .padding(.vertical, Tokens.Spacing.s1)
                    .padding(.trailing, Tokens.Spacing.s2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("Connect \(viewModel.providerName)")
                .font(Tokens.Typography.Onboarding.windowTitle)
                .foregroundStyle(Tokens.Color.textMuted(scheme))

            Spacer()

            // Invisible balance for centering when there's a back button.
            if backInHeader {
                HStack(spacing: Tokens.Spacing.s1) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(Tokens.Typography.Onboarding.small.weight(.medium))
                .hidden()
            }
        }
    }

    /// True when the current step view renders its own footer back link
    /// (via `WindowFooter`). The header back is hidden in that case.
    private var stepHasOwnBack: Bool {
        switch viewModel.step {
        case .detecting, .confirmingInstall, .openProviderSite,
             .previewExternalSteps, .awaitingExternalAuth, .pasteAPIKey:
            return true
        default:
            return false
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .connected(let plan):
            connectedState(plan: plan)
        case .failed(let error):
            errorState(error: error)
        case .detecting:
            DetectStep(items: detectionItems(for: viewModel.providerId),
                       subtitle: detectSubtitle(for: viewModel.providerId),
                       onBack: onBack)
        case .confirmingInstall(let title, let body, let commandPreview, let footnote, let skipLabel):
            ConfirmInstallStep(
                title: title,
                description: body,
                commandPreview: commandPreview,
                footnote: footnote,
                skipLabel: skipLabel,
                onContinue: { viewModel.tappedConfirmInstall() },
                onSkip: { viewModel.tappedSkipInstall() },
                onBack: onBack
            )
        case .previewExternalSteps(let headline, let body, let groupLabel, let startingNumber, let items, let primaryLabel, let headsUp):
            PreviewExternalStepsView(
                headline: headline,
                introText: body,
                groupLabel: groupLabel,
                startingNumber: startingNumber,
                items: items,
                primaryLabel: primaryLabel,
                headsUp: headsUp,
                onPrimary: { viewModel.tappedAdvancePreview() },
                onBack: onBack
            )
        case .awaitingExternalAuth(let headline, let body):
            AwaitExternalAuthView(
                headline: headline,
                instructionText: body,
                onCheckNow: { viewModel.tappedRecheck() },
                onBack: onBack
            )
        case .openProviderSite(let headline, let body, let ctaLabel):
            // Pattern E step 1 — reuses the confirm-screen chrome with provider-site framing.
            ConfirmInstallStep(
                title: headline,
                description: body,
                commandPreview: nil,
                footnote: "You only do this once — the key lives in macOS Keychain after this; Tokenomics never sees it again after you paste it.",
                skipLabel: "Already have a key? Skip to paste",
                primaryLabel: ctaLabel,
                onContinue: { viewModel.tappedConfirmInstall() },
                onSkip: { viewModel.tappedSkipInstall() },
                onBack: onBack
            )
        case .pasteAPIKey(let providerName, let helpURL):
            // Pattern E step 2 — secure paste field. Back goes to the "Get
            // API key" step (not the chooser) — the user is mid-flow and
            // may want to re-read the instructions or re-open the dashboard.
            APIKeyPasteStep(
                providerName: providerName,
                helpURL: helpURL,
                onSubmit: { key in viewModel.tappedSubmitAPIKey(key) },
                onBack: { viewModel.tappedBackOneStep() }
            )
        default:
            inProgressState
        }
    }

    // MARK: - In-progress state (shared "before connected" body)

    private var inProgressState: some View {
        VStack(alignment: .leading, spacing: 0) {
            connectorHeader

            statusPill

            helpLink
                .padding(.top, Tokens.Spacing.s1 - 2)

            actionStack
                .padding(.top, Tokens.Spacing.s7 - 12) // 36pt breathing room above CTA
        }
    }

    private var connectorHeader: some View {
        HStack(alignment: .center, spacing: 11) {
            ProviderIcon(provider: viewModel.providerId, size: .lg)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.providerName)
                    .font(Tokens.Typography.Onboarding.h3)
                    .foregroundStyle(Tokens.Color.text(scheme))

                Text(headerSubtext)
                    .font(Tokens.Typography.Onboarding.small)
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, Tokens.Spacing.s2)
    }

    /// Sub-line under the provider name — varies by step.
    private var headerSubtext: String {
        switch viewModel.step {
        case .detecting:
            return "Checking your Mac…"
        case .needsAction:
            return needsActionSubtext(for: viewModel.providerId)
        case .waitingForExternalApp:
            return "Waiting for \(viewModel.providerName) to install…"
        case .installingDependency(let name, _):
            return "Installing \(name)…"
        case .installing:
            return "Setting up — only happens once."
        case .confirmingInstall:
            return "Almost there."
        case .awaitingUserConfirm:
            return "One quick confirmation before we continue."
        case .awaitingOAuth:
            return "Sign in in your browser to continue."
        case .previewExternalSteps, .awaitingExternalAuth, .openProviderSite, .pasteAPIKey:
            return ""
        case .connected:
            return "Connected."
        case .failed:
            return "Something didn't go through."
        case .skipped:
            return ""
        }
    }

    // MARK: - Status pill

    @ViewBuilder
    private var statusPill: some View {
        switch viewModel.step {
        case .detecting, .confirmingInstall, .previewExternalSteps, .awaitingExternalAuth,
             .openProviderSite, .pasteAPIKey, .needsAction:
            EmptyView()
        case .waitingForExternalApp:
            statusBadge(icon: .waiting, text: "Waiting for \(viewModel.providerName) — we'll detect it as soon as it's installed.")
        case .installingDependency(_, let progress):
            installingPill(progress: progress)
        case .installing(let progress):
            installingPill(progress: progress)
        case .awaitingUserConfirm(let message):
            statusBadge(icon: .waiting, text: message)
        case .awaitingOAuth(let code):
            statusBadge(icon: .waiting, text: "Waiting for you to approve in your browser…")
            if let code, !code.isEmpty {
                deviceCodeRow(code)
                    .padding(.top, Tokens.Spacing.s2)
            }
        case .connected, .failed, .skipped:
            EmptyView()
        }
    }

    private var helpLink: some View {
        let anchor = viewModel.providerId.setupGuideAnchor
        let url = URL(string: "https://trytokenomics.com/setup.html\(anchor)")
        return HStack {
            Spacer()
            if let url {
                Link(destination: url) {
                    Text("Need help? Step-by-step guide")
                        .font(Tokens.Typography.Onboarding.micro)
                        .foregroundStyle(Tokens.Color.textSubtle(scheme))
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var actionStack: some View {
        VStack(spacing: Tokens.Spacing.s2 + 2) { // 10pt
            Button(primaryCTALabel) {
                viewModel.tappedPrimary()
            }
            .buttonStyle(.tokenPrimary)

            Button("Cancel") {
                viewModel.tappedCancel()
                onBack?()
            }
            .buttonStyle(.tokenGhost)
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryCTALabel: String {
        switch viewModel.step {
        case .detecting, .confirmingInstall, .previewExternalSteps, .awaitingExternalAuth,
             .openProviderSite, .pasteAPIKey:
            return ""
        case .needsAction:
            return primaryCTA(for: viewModel.providerId)
        case .waitingForExternalApp:
            return "Check now"
        case .installingDependency:
            return "Installing…"
        case .installing:
            return "Setting up…"
        case .awaitingUserConfirm:
            return "Open browser to sign in"
        case .awaitingOAuth:
            return "Reopen browser"
        case .connected:
            return "Continue"
        case .failed(let error):
            return error.recoveryActionLabel
        case .skipped:
            return ""
        }
    }

    // MARK: - Connected state

    private func connectedState(plan: String) -> some View {
        VStack(spacing: 0) {
            // Done check — design-system.md: 64×64 circle, success@16% alpha, success checkmark
            ZStack {
                Circle()
                    .fill(Tokens.Color.success(scheme).opacity(0.16))
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Tokens.Color.success(scheme))
            }
            .frame(width: 64, height: 64)
            .padding(.top, Tokens.Spacing.s1 + 2)
            .padding(.bottom, Tokens.Spacing.s4 + 2) // 18pt

            Text("\(viewModel.providerName) is connected.")
                .font(Tokens.Typography.Onboarding.h1)
                .foregroundStyle(Tokens.Color.text(scheme))
                .multilineTextAlignment(.center)

            Text("Tokenomics is now reading your \(viewModel.providerName) usage.")
                .font(Tokens.Typography.Onboarding.lede)
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, Tokens.Spacing.s1)

            Text("Want to add another, or jump in?")
                .font(Tokens.Typography.Onboarding.lede)
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .padding(.top, Tokens.Spacing.s1)
                .multilineTextAlignment(.center)

            VStack(spacing: Tokens.Spacing.s2 + 2) { // 10pt
                Button("Add another provider") {
                    viewModel.tappedAddAnother()
                }
                .buttonStyle(.tokenPrimary)

                Button("I'm all set") {
                    viewModel.tappedAllSet()
                }
                .buttonStyle(.tokenGhost)
            }
            .padding(.top, Tokens.Spacing.s7 - 12) // 36pt

            Text("Add or remove anytime in **Settings → Connections**.")
                .font(Tokens.Typography.Onboarding.small)
                .foregroundStyle(Tokens.Color.textSubtle(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, Tokens.Spacing.s3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error state

    /// Inline failure block — mockup .errblock pattern:
    ///   bg danger@8%, border danger@30%, r-sm, 14px semibold danger heading.
    private func errorState(error: ConnectorError) -> some View {
        VStack(spacing: 0) {
            connectorHeader

            // Error block — mockup .errblock (lines 1022–1032)
            VStack(alignment: .leading, spacing: Tokens.Spacing.s1) {
                Text(error.userFacingMessage)
                    .font(Tokens.Typography.Onboarding.body.weight(.semibold))
                    .foregroundStyle(Tokens.Color.danger(scheme))

                // Recovery hint below heading if the message is short
                if let detail = errorDetail(for: error) {
                    Text(detail)
                        .font(Tokens.Typography.Onboarding.small)
                        .foregroundStyle(Tokens.Color.textMuted(scheme))
                        .padding(.top, Tokens.Spacing.s1 - 2)
                }
            }
            .padding(.horizontal, Tokens.Spacing.s4)
            .padding(.vertical, Tokens.Spacing.s4 - 2) // 14pt
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Color.danger(scheme).opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                    .strokeBorder(Tokens.Color.danger(scheme).opacity(0.30), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
            .padding(.top, Tokens.Spacing.s4)

            VStack(spacing: Tokens.Spacing.s2 + 2) { // 10pt
                Button(error.recoveryActionLabel) {
                    if case .automationPermissionDenied = error {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    } else if case .permissionDenied = error {
                        viewModel.tappedPermissionDeniedRecovery()
                    } else {
                        viewModel.tappedRecovery()
                    }
                }
                .buttonStyle(.tokenPrimary)

                if let onBack {
                    Button("Cancel") { onBack() }
                        .buttonStyle(.tokenGhost)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Tokens.Spacing.s7 - 12) // 36pt
        }
    }

    private func errorDetail(for error: ConnectorError) -> String? {
        switch error {
        case .permissionDenied:
            return "EACCES: permission denied — try the per-user install path."
        case .automationPermissionDenied:
            return "Open System Settings → Privacy & Security → Automation to grant access."
        default:
            return nil
        }
    }

    // MARK: - Piece views

    private enum BadgeIcon { case waiting, success, warning }

    private func statusBadge(icon: BadgeIcon, text: String) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Group {
                switch icon {
                case .waiting:
                    ProgressView().controlSize(.small)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Tokens.Color.success(scheme))
                case .warning:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Tokens.Color.warning(scheme))
                }
            }
            .frame(width: 14, height: 14)

            Text(text)
                .font(Tokens.Typography.Onboarding.small)
                .foregroundStyle(Tokens.Color.text(scheme))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Tokens.Color.surface2(scheme))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }

    private func installingPill(progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s1 + 2) { // 6pt
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Tokens.Color.accent(scheme))
            HStack {
                Text("Almost there")
                    .font(Tokens.Typography.Onboarding.micro)
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                Spacer()
                if let progress {
                    Text("\(Int(progress * 100))%")
                        .font(Tokens.Typography.Onboarding.micro)
                        .foregroundStyle(Tokens.Color.textMuted(scheme))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Tokens.Color.surface2(scheme))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }

    private func deviceCodeRow(_ code: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("If asked for a code")
                    .font(Tokens.Typography.Onboarding.micro)
                    .foregroundStyle(Tokens.Color.textSubtle(scheme))
                    .textCase(.uppercase)
                Text(code)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Tokens.Color.text(scheme))
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(Tokens.Typography.Onboarding.small)
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
            }
            .buttonStyle(.plain)
            .help("Copy code")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .strokeBorder(
                    Tokens.Color.borderStrong(scheme).opacity(0.6),
                    style: StrokeStyle(lineWidth: 0.5, dash: [3])
                )
        )
    }

    // MARK: - Per-provider copy helpers

    private func needsActionSubtext(for provider: ProviderId) -> String {
        switch provider {
        case .cursor: return "Tokenomics reads usage from the Cursor app on your Mac."
        case .copilot: return "Sign in once and we'll track your Copilot usage."
        case .claude: return "Sign in to your Anthropic account."
        case .codex: return "Sign in with your ChatGPT account."
        case .gemini: return "Sign in with your Google account."
        case .stableDiffusion, .runway, .elevenlabs: return "Paste an API key from the provider's website."
        default: return "Connect this provider to track its usage."
        }
    }

    private func primaryCTA(for provider: ProviderId) -> String {
        switch provider {
        case .cursor: return "Connect Cursor"
        case .copilot: return "Sign in with GitHub"
        case .claude: return "Sign in with Anthropic"
        case .codex: return "Sign in with OpenAI"
        case .gemini: return "Sign in with Google"
        case .stableDiffusion, .runway, .elevenlabs: return "Enter API key"
        default: return "Connect"
        }
    }

    private func detectSubtitle(for provider: ProviderId) -> String {
        switch provider {
        case .codex:   return "Looking for the tools needed to connect Codex."
        case .gemini:  return "Looking for the tools needed to connect Gemini."
        case .claude:  return "Looking for the tools needed to connect Claude Code."
        case .copilot: return "Looking for the tools needed to connect Copilot."
        case .cursor:  return "Checking for the Cursor app…"
        default:       return "Checking your Mac…"
        }
    }

    /// Builds the per-prereq DetectionItem list from `SystemPrerequisiteDetector`'s
    /// synchronous filesystem checks. Empty for providers without a prereq chain
    /// (Cursor app-bundle wait, API-key paste) — DetectStep falls back to spinner.
    private func detectionItems(for provider: ProviderId) -> [DetectionItem] {
        switch provider {
        case .codex:
            return [
                brewItem(),
                nodeItem(),
                npmCLIItem(name: "Codex CLI", binary: "codex", package: "@openai/codex"),
            ]
        case .gemini:
            return [
                brewItem(),
                nodeItem(),
                npmCLIItem(name: "Gemini CLI", binary: "gemini", package: "@google/gemini-cli"),
            ]
        case .claude:
            // Claude Code ships as a Homebrew cask — no Node needed.
            return [
                brewItem(),
                claudeItem(),
            ]
        case .copilot:
            return [
                brewItem(),
                ghItem(),
            ]
        default:
            // Cursor (app-bundle), API-key providers, etc. — spinner fallback.
            return []
        }
    }

    // MARK: - DetectionItem builders (synchronous filesystem reads)

    private func brewItem() -> DetectionItem {
        if let url = SystemPrerequisiteDetector.homebrewPath() {
            return DetectionItem(name: "Homebrew", sublabel: url.path, status: .installed)
        }
        return DetectionItem(name: "Homebrew",
                             sublabel: "Package manager for macOS",
                             status: .notInstalled)
    }

    private func nodeItem() -> DetectionItem {
        if let url = SystemPrerequisiteDetector.nodePath() {
            // Node + version (best-effort — read symlink target if available)
            return DetectionItem(name: "Node.js",
                                 nameSuffix: "(includes npm)",
                                 sublabel: url.path,
                                 status: .installed)
        }
        return DetectionItem(name: "Node.js",
                             nameSuffix: "(includes npm)",
                             sublabel: "Required by the CLI",
                             status: .notInstalled)
    }

    private func npmCLIItem(name: String, binary: String, package: String) -> DetectionItem {
        if let url = SystemPrerequisiteDetector.tokenomicsNpmBinPath(binary) {
            return DetectionItem(name: name, sublabel: url.path, status: .installed)
        }
        return DetectionItem(name: name, sublabel: package, status: .notInstalled)
    }

    private func claudeItem() -> DetectionItem {
        let candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return DetectionItem(name: "Claude Code", sublabel: path, status: .installed)
        }
        return DetectionItem(name: "Claude Code",
                             sublabel: "Anthropic's CLI",
                             status: .notInstalled)
    }

    private func ghItem() -> DetectionItem {
        if let url = SystemPrerequisiteDetector.ghPath() {
            return DetectionItem(name: "GitHub CLI",
                                 nameSuffix: "(gh)",
                                 sublabel: url.path,
                                 status: .installed)
        }
        return DetectionItem(name: "GitHub CLI",
                             nameSuffix: "(gh)",
                             sublabel: "Used to authenticate Copilot",
                             status: .notInstalled)
    }
}
