import Foundation
import AppKit
import os

/// Guided-mode connector for OpenAI's Codex CLI.
///
/// Flow (system-Node path):
///   1. `.detecting` — `SystemPrerequisiteDetector` checks Homebrew → Node → Codex CLI in parallel.
///   2. For each missing prerequisite, the connector waits in `.confirmingInstall` until the
///      user taps "Continue". Then it installs via `GuidedInstallRunner` and re-detects.
///   3. Once all prerequisites are present, it launches `codex login` as a hidden subprocess
///      and transitions to `.awaitingOAuth`.
///   4. The polling loop re-calls `currentStep()` every 1.5s. When `~/.codex/auth.json`
///      appears, `CodexProvider` returns `.connected` and the flow is done.
///
/// Policy note: Tokenomics runs `codex login` (the official CLI auth flow) as a subprocess
/// and reads the local auth.json it produces. No OpenAI backend calls are made directly.
actor CodexConnector: ProviderConnector {
    nonisolated let id: ProviderId = .codex
    nonisolated let pipelineKind: ConnectorPipelineKind = .multiStep

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CodexConnector")
    private static let npmPackage = "@openai/codex"

    private let provider: CodexProvider
    private let runner: GuidedInstallRunner

    // MARK: - Internal state machine

    /// Which prerequisite (or login phase) the connector is currently handling.
    private enum ActivePhase {
        case none
        /// Waiting for user to confirm before installing a prerequisite or the CLI itself.
        case confirmingInstall(PrerequisiteKind)
        /// Installing a prerequisite (Homebrew, Node.js).
        case installingDependency(name: String, progress: Double?)
        /// Installing the primary Codex CLI.
        case installingCLI(progress: Double?)
        /// `codex login` is running; waiting for the OAuth browser flow to complete.
        case awaitingOAuth(code: String?)
    }

    private enum PrerequisiteKind {
        case homebrew, node, codexCLI
    }

    private var activePhase: ActivePhase = .none

    /// First-poll latch: when the connector enters in `.notInstalled`, the
    /// initial `currentStep()` returns `.detecting` and kicks off the prereq
    /// chain in the background. Subsequent polls return `.detecting` until the
    /// chain transitions `activePhase` to `.confirmingInstall(...)`. Reset on
    /// `clearFailure()` so retry replays the same intro.
    private var didStartDetection = false

    /// When set, `currentStep()` returns `.failed` immediately. Cleared on cancel/skip.
    private var failedState: ConnectorError?

    // MARK: - Init

    init(provider: CodexProvider = CodexProvider()) {
        self.provider = provider
        self.runner = GuidedInstallRunner()
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
            // Peek at the provider — auth.json may have just appeared.
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
        case .notInstalled:
            // Land on the prereq checklist, not the misleading "Sign in with
            // OpenAI" CTA. Kick off the chain async — by the next 1.5s poll
            // tick activePhase will be `.confirmingInstall(.homebrew)` (or
            // whichever prereq is missing first).
            if !didStartDetection {
                didStartDetection = true
                Task { await self.startPrerequisiteChain() }
            }
            return .detecting
        case .installedNoAuth, .authExpired, .needsKeychainAccess:
            // Prereqs are all there — only sign-in remains. Still show the
            // "Checking your Mac" interstitial once so the user gets the
            // same coherent flow regardless of what was already installed
            // (Bug B).
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
            // User tapped "Reopen browser" — re-launch login.
            await launchLogin()
            return
        case .none:
            break
        default:
            // Mid-install — nothing to do on primary tap.
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
        // Re-arm so retry replays the detect → install intro.
        didStartDetection = false
    }

    func clearInstallCache() async {
        await runner.clearNpmCache()
    }

    func confirmInstall() async {
        guard case .confirmingInstall(let kind) = activePhase else { return }
        switch kind {
        case .homebrew:
            await installHomebrew()
        case .node:
            await installNode()
        case .codexCLI:
            await installCLI()
        }
    }

    func skipInstall() async {
        // User claims the prerequisite is already installed — re-detect from scratch.
        activePhase = .none
        failedState = nil
        await startPrerequisiteChain()
    }

    // MARK: - Prerequisite chain

    /// Checks which prerequisites are missing and starts the confirm → install flow
    /// for the first missing one. Each install step transitions cleanly to the next.
    private func startPrerequisiteChain() async {
        if SystemPrerequisiteDetector.homebrewPath() == nil {
            activePhase = .confirmingInstall(.homebrew)
            return
        }
        if SystemPrerequisiteDetector.nodePath() == nil {
            activePhase = .confirmingInstall(.node)
            return
        }
        if codexBinaryURL() == nil {
            activePhase = .confirmingInstall(.codexCLI)
            return
        }
        // Everything present — go straight to login.
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

    private func installNode() async {
        guard let brewPath = SystemPrerequisiteDetector.homebrewPath() else {
            Self.log.error("brew not found — cannot install Node.js")
            activePhase = .none
            failedState = .missingPrerequisite("Homebrew")
            return
        }
        activePhase = .installingDependency(name: "Node.js", progress: nil)
        do {
            let events = try await runner.installViaHomebrew(brewPath: brewPath, formula: "node", isCask: false)
            for await event in events {
                switch event {
                case .progress(let p):
                    activePhase = .installingDependency(name: "Node.js", progress: p)
                case .log(let line):
                    Self.log.debug("[node install] \(line)")
                case .completed:
                    Self.log.info("Node.js installed successfully")
                    activePhase = .none
                    await startPrerequisiteChain()
                    return
                case .failed(let reason):
                    Self.log.error("Node.js install failed: \(reason)")
                    activePhase = .none
                    failedState = classifyBrewFormulaFailure(reason)
                }
            }
        } catch {
            Self.log.error("Node.js install error: \(error.localizedDescription)")
            activePhase = .none
            failedState = .cliInstallFailed(error.localizedDescription)
        }
    }

    private func installCLI() async {
        guard let npmPath = SystemPrerequisiteDetector.npmPath() else {
            Self.log.error("npm not found — cannot install Codex CLI")
            activePhase = .none
            failedState = .missingPrerequisite("Node.js")
            return
        }
        activePhase = .installingCLI(progress: nil)
        do {
            let events = try await runner.installNpmPackage(npmPath: npmPath, package: Self.npmPackage)
            for await event in events {
                switch event {
                case .progress(let p):
                    activePhase = .installingCLI(progress: p)
                case .log(let line):
                    Self.log.debug("[npm] \(line)")
                case .completed:
                    Self.log.info("Codex CLI installed successfully")
                    await launchLogin()
                    return
                case .failed(let reason):
                    Self.log.error("Codex CLI install failed: \(reason)")
                    activePhase = .none
                    failedState = classifyNpmFailure(reason)
                }
            }
        } catch {
            Self.log.error("Codex CLI install error: \(error.localizedDescription)")
            activePhase = .none
            failedState = .cliInstallFailed(error.localizedDescription)
        }
    }

    private func classifyNpmFailure(_ reason: String) -> ConnectorError {
        if reason.hasPrefix("EACCES:") {
            let path = String(reason.dropFirst("EACCES:".count))
            return .permissionDenied(path: path)
        }
        return .cliInstallFailed(reason)
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
        // AppleScript parser errors are Tokenomics bugs, not user-actionable —
        // log the raw text and show generic copy.
        let technicalMarkers = ["unknown token", "syntax error", "expected", "applescript",
                                "osascript", "nsapplescripterror", "errosacanttellwhat"]
        if technicalMarkers.contains(where: lower.contains) {
            Self.log.error("Suppressing technical Homebrew error from UI: \(reason, privacy: .public)")
            return .cliInstallFailed("")
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

    // MARK: - Login pipeline

    /// Resolves the codex binary — checks system paths then the Tokenomics per-user npm prefix.
    private func codexBinaryURL() -> URL? {
        let systemPaths = [
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
            "/opt/homebrew/bin/codex",
        ]
        let fm = FileManager.default
        for path in systemPaths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return SystemPrerequisiteDetector.tokenomicsNpmBinPath("codex")
    }

    private func launchLogin() async {
        guard let binary = codexBinaryURL() else {
            Self.log.error("codex binary not found — cannot launch login")
            activePhase = .none
            return
        }

        activePhase = .awaitingOAuth(code: nil)

        do {
            let handle = try await runner.runCommand(executable: binary, args: ["login"])
            for await event in handle.events {
                switch event {
                case .stdout(let line):
                    Self.log.debug("[codex stdout] \(line)")
                case .stderr(let line):
                    Self.log.debug("[codex stderr] \(line)")
                case .deviceCode(let url, let code):
                    activePhase = .awaitingOAuth(code: code)
                    await openOnMain(url)
                    Self.log.info("Codex device-code URL detected: \(url)")
                case .exited(let code):
                    Self.log.info("codex login exited with code \(code)")
                    // Don't clear phase — let the polling loop detect auth.json.
                }
            }
        } catch {
            Self.log.error("codex login error: \(error.localizedDescription)")
            activePhase = .none
        }
    }

    // MARK: - Helpers

    private func confirmStep(for kind: PrerequisiteKind) -> ConnectorStep {
        switch kind {
        case .homebrew:
            return .confirmingInstall(
                title: "Install Homebrew",
                body: "Tokenomics needs Homebrew to install Codex. Homebrew is the standard Mac package manager — about 2 minutes to install.",
                commandPreview: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
                footnote: "We'll open Terminal and install Homebrew with your permission. You'll be asked for your password once. This is Homebrew's official installer, straight from brew.sh.",
                skipLabel: "Already have Homebrew? Skip this step"
            )
        case .node:
            return .confirmingInstall(
                title: "Install Node.js",
                body: "Now we'll install Node.js using Homebrew. About 30 seconds, no extra permissions needed.",
                commandPreview: "brew install node",
                footnote: "Tokenomics installs Node.js into ~/.tokenomics-cli so it stays separate from any Node you might install later.",
                skipLabel: "Already have Node.js? Skip this step"
            )
        case .codexCLI:
            return .confirmingInstall(
                title: "Install Codex CLI",
                body: "Tokenomics will install OpenAI's command-line Codex tool. About 30 seconds.",
                commandPreview: "npm install -g @openai/codex",
                footnote: "Installed to ~/.tokenomics-cli — keeps Tokenomics' tools out of your global npm.",
                skipLabel: "Already have Codex? Skip this step"
            )
        }
    }

    @MainActor
    private func openOnMain(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
