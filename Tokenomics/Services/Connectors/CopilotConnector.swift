import Foundation
import AppKit
import os

/// Guided-mode connector for GitHub Copilot.
///
/// Flow (Pattern C — two confirms + `gh auth login`):
///   1. `currentStep()` checks for Homebrew and the `gh` CLI.
///   2. If Homebrew missing: `.confirmingInstall(.homebrew)` → install → re-detect.
///   3. If `gh` missing: `.confirmingInstall(.ghCLI)` → `brew install gh` → re-detect.
///   4. Once both are present, runs `gh auth login --web --git-protocol=https` as a
///      hidden subprocess. The device-code URL (GitHub's OAuth redirect) opens
///      automatically in the user's browser.
///   5. Polling loop re-calls `currentStep()` every 1.5s. When `CopilotProvider`
///      returns `.connected`, the flow is done.
///
/// Legacy PAT path: `onRequestAuth` fires the PAT sheet for power users who arrive
/// through AIConnectionsView's dormant sheet path. The guided window always uses
/// the `gh auth login` flow above.
actor CopilotConnector: ProviderConnector {
    nonisolated let id: ProviderId = .copilot
    nonisolated let pipelineKind: ConnectorPipelineKind = .multiStep

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CopilotConnector")

    private let provider: CopilotProvider
    private let runner: GuidedInstallRunner

    /// Legacy escape hatch — fires the PAT sheet if the connector is instantiated
    /// with an auth callback (Settings → Connections PAT flow). Nil in guided window.
    private let onRequestAuth: (@Sendable @MainActor () -> Void)?  // optional = implicitly escaping

    // MARK: - Internal state machine

    private enum ActivePhase {
        /// No action in progress — detect from scratch.
        case none
        /// Waiting for user to confirm an install step.
        case confirmingInstall(PrerequisiteKind)
        /// Installing Homebrew (as a dependency).
        case installingDependency(name: String, progress: Double?)
        /// Installing the `gh` CLI via Homebrew.
        case installingCLI(progress: Double?)
        /// `gh auth login` is running; waiting for the OAuth browser flow to complete.
        case awaitingOAuth(code: String?)
    }

    private enum PrerequisiteKind {
        case homebrew, ghCLI
    }

    private var activePhase: ActivePhase = .none

    /// When set, `currentStep()` returns `.failed` immediately. Cleared on cancel/skip.
    private var failedState: ConnectorError?

    /// Have we shown the "Checking your Mac" intro yet this session?
    /// Used to display the DetectStep once before transitioning to the
    /// appropriate needsAction CTA, so the flow feels consistent regardless
    /// of whether `gh` was already installed (Bug B).
    private var didStartDetection = false

    // MARK: - Init

    init(provider: CopilotProvider = CopilotProvider(),
         onRequestAuth: (@Sendable @MainActor () -> Void)? = nil) {
        self.provider = provider
        self.runner = GuidedInstallRunner()
        self.onRequestAuth = onRequestAuth
    }

    // MARK: - ProviderConnector

    func currentStep() async -> ConnectorStep {
        if let failure = failedState { return .failed(failure) }

        switch activePhase {
        case .confirmingInstall(let kind):
            return confirmStep(for: kind)

        case .installingDependency(let name, let progress):
            return .installingDependency(name: name, progress: progress)

        case .installingCLI(let progress):
            return .installing(progress: progress)

        case .awaitingOAuth(let code):
            // Peek at the provider — the gh token may have just appeared.
            let state = await provider.checkConnection()
            if case .connected(let plan) = state {
                activePhase = .none
                return .connected(plan: plan)
            }
            return .awaitingOAuth(code: code)

        case .none:
            break
        }

        // No active phase — delegate to provider for terminal states.
        let state = await provider.checkConnection()
        switch state {
        case .connected(let plan):
            return .connected(plan: plan)
        case .notInstalled, .installedNoAuth, .authExpired, .needsKeychainAccess:
            // Show "Checking your Mac" interstitial once before the
            // needsAction CTA — keeps the onboarding flow visually
            // consistent across providers (Bug B).
            if !didStartDetection {
                didStartDetection = true
                return .detecting
            }
            return .needsAction
        case .unavailable(let reason):
            return .failed(.unknown(reason))
        }
    }

    func performPrimaryAction() async {
        switch activePhase {
        case .awaitingOAuth:
            // "Reopen browser" — re-launch gh auth login.
            await launchLogin()
            return
        case .none:
            break
        default:
            return
        }

        // Legacy PAT path: if the connector was initialised with a PAT callback and
        // gh is already installed, surface the PAT sheet instead of the guided flow.
        if let onRequestAuth, SystemPrerequisiteDetector.ghPath() != nil {
            await MainActor.run { onRequestAuth() }
            return
        }

        let state = await provider.checkConnection()
        switch state {
        case .connected:
            return
        case .notInstalled:
            await startPrerequisiteChain()
        case .installedNoAuth, .authExpired, .needsKeychainAccess:
            await launchLogin()
        case .unavailable:
            return
        }
    }

    func cancel() async {
        await runner.cancel()
        activePhase = .none
        failedState = nil
        didStartDetection = false
    }

    func clearFailure() async {
        failedState = nil
        activePhase = .none
        // Re-arm so retry replays the detect intro.
        didStartDetection = false
    }

    func confirmInstall() async {
        guard case .confirmingInstall(let kind) = activePhase else { return }
        switch kind {
        case .homebrew:
            await installHomebrew()
        case .ghCLI:
            await installGhCLI()
        }
    }

    func skipInstall() async {
        activePhase = .none
        failedState = nil
        await startPrerequisiteChain()
    }

    // MARK: - Prerequisite chain

    private func startPrerequisiteChain() async {
        if SystemPrerequisiteDetector.homebrewPath() == nil {
            activePhase = .confirmingInstall(.homebrew)
            return
        }
        if SystemPrerequisiteDetector.ghPath() == nil {
            activePhase = .confirmingInstall(.ghCLI)
            return
        }
        // Both present — go straight to login.
        await launchLogin()
    }

    // MARK: - Install steps

    private func installHomebrew() async {
        activePhase = .installingDependency(name: "Homebrew", progress: nil)
        do {
            let events = try await runner.installHomebrew()
            for await event in events {
                switch event {
                case .progress(let p):
                    activePhase = .installingDependency(name: "Homebrew", progress: p)
                case .log(let line):
                    Self.log.debug("[brew] \(line)")
                case .completed:
                    Self.log.info("Homebrew installed successfully")
                    activePhase = .none
                    await startPrerequisiteChain()
                    return
                case .failed(let reason):
                    Self.log.error("Homebrew install failed: \(reason)")
                    activePhase = .none
                    failedState = classifyHomebrewFailure(reason)
                }
            }
        } catch {
            Self.log.error("Homebrew install error: \(error.localizedDescription)")
            activePhase = .none
            failedState = .cliInstallFailed(error.localizedDescription)
        }
    }

    private func installGhCLI() async {
        guard let brewPath = SystemPrerequisiteDetector.homebrewPath() else {
            Self.log.error("brew not found — cannot install gh")
            activePhase = .none
            failedState = .missingPrerequisite("Homebrew")
            return
        }
        activePhase = .installingCLI(progress: nil)
        do {
            let events = try await runner.installViaHomebrew(brewPath: brewPath, formula: "gh", isCask: false)
            for await event in events {
                switch event {
                case .progress(let p):
                    activePhase = .installingCLI(progress: p)
                case .log(let line):
                    Self.log.debug("[gh install] \(line)")
                case .completed:
                    Self.log.info("gh CLI installed successfully")
                    activePhase = .none
                    await launchLogin()
                    return
                case .failed(let reason):
                    Self.log.error("gh install failed: \(reason)")
                    activePhase = .none
                    failedState = classifyBrewFormulaFailure(reason)
                }
            }
        } catch {
            Self.log.error("gh install error: \(error.localizedDescription)")
            activePhase = .none
            failedState = .cliInstallFailed(error.localizedDescription)
        }
    }

    // MARK: - Login pipeline

    private func launchLogin() async {
        guard let ghURL = SystemPrerequisiteDetector.ghPath() else {
            Self.log.error("gh binary not found — cannot launch auth login")
            activePhase = .none
            failedState = .missingPrerequisite("GitHub CLI (gh)")
            return
        }

        activePhase = .awaitingOAuth(code: nil)

        do {
            let handle = try await runner.runCommand(
                executable: ghURL,
                args: ["auth", "login", "--web", "--git-protocol=https"]
            )

            for await event in handle.events {
                switch event {
                case .stdout(let line):
                    Self.log.debug("[gh stdout] \(line)")
                case .stderr(let line):
                    Self.log.debug("[gh stderr] \(line)")
                case .deviceCode(let url, let code):
                    // gh prints a device code and opens the browser; surface the code
                    // in the UI so the user can paste it if the browser doesn't auto-fill.
                    activePhase = .awaitingOAuth(code: code)
                    await openOnMain(url)
                    Self.log.info("gh auth device-code URL: \(url)")
                case .exited(let code):
                    Self.log.info("gh auth login exited with code \(code)")
                    // Don't clear phase — let the polling loop detect the gh token.
                }
            }
        } catch {
            Self.log.error("gh auth login error: \(error.localizedDescription)")
            activePhase = .none
        }
    }

    // MARK: - Failure classification

    private func classifyHomebrewFailure(_ reason: String) -> ConnectorError {
        let lower = reason.lowercased()
        if lower.contains("user canceled") || lower.contains("errAEEventNotPermitted".lowercased())
            || lower.contains("not allowed to send apple events") {
            return .homebrewInstallCancelled
        }
        if lower.contains("curl") || lower.contains("network") || lower.contains("connection refused")
            || lower.contains("could not resolve host") {
            return .homebrewNotReachable
        }
        return .cliInstallFailed(reason)
    }

    private func classifyBrewFormulaFailure(_ reason: String) -> ConnectorError {
        if reason.hasPrefix("EACCES:") {
            let path = String(reason.dropFirst("EACCES:".count))
            return .permissionDenied(path: path)
        }
        let lower = reason.lowercased()
        if lower.contains("network") || lower.contains("curl") || lower.contains("connection refused") {
            return .homebrewNotReachable
        }
        return .cliInstallFailed(reason)
    }

    // MARK: - Confirm step copy

    private func confirmStep(for kind: PrerequisiteKind) -> ConnectorStep {
        switch kind {
        case .homebrew:
            return .confirmingInstall(
                title: "Install Homebrew",
                body: "Tokenomics needs Homebrew to install the GitHub CLI. Homebrew is the standard Mac package manager — about 2 minutes to install.",
                commandPreview: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
                footnote: "We'll open Terminal and install Homebrew with your permission. You'll be asked for your password once. This is Homebrew's official installer, straight from brew.sh.",
                skipLabel: "Already have Homebrew? Skip this step"
            )
        case .ghCLI:
            return .confirmingInstall(
                title: "Install GitHub CLI",
                body: "Now we'll install the GitHub CLI (gh). It's what connects Tokenomics to your Copilot account — no GitHub token setup needed.",
                commandPreview: "brew install gh",
                footnote: "The GitHub CLI is GitHub's official tool for connecting to your account. Tokenomics runs `gh auth login` after this — same flow you'd use in Terminal.",
                skipLabel: "Already have gh? Skip this step"
            )
        }
    }

    // MARK: - Helpers

    @MainActor
    private func openOnMain(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
