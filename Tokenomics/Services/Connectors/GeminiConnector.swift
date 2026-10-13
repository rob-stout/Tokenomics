import Foundation
import AppKit
import os

/// Guided-mode connector for Google's Gemini CLI.
///
/// Flow is parallel to `CodexConnector` — see that file for full architecture notes.
///
/// Gemini specifics vs Codex:
///   - npm package: `@google/gemini-cli`
///   - Auth file: `~/.gemini/oauth_creds.json`
///   - Login trigger: `gemini` (no explicit `login` subcommand — the CLI starts an OAuth
///     flow on first invocation when no creds are found).
///   - Confirm-prompt interception: Gemini prints "Do you want to continue? [Y/n]:" before
///     opening the browser. We park in `.awaitingUserConfirm` so the user's click in
///     Tokenomics' UI — not an auto-answered terminal prompt — is what grants consent.
///
/// Policy note: Tokenomics runs `gemini` as a subprocess (the official CLI auth flow) and
/// reads the local `oauth_creds.json` it produces. No Google backend calls are made directly.
actor GeminiConnector: ProviderConnector {
    nonisolated let id: ProviderId = .gemini
    nonisolated let pipelineKind: ConnectorPipelineKind = .multiStep

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "GeminiConnector")
    private static let npmPackage = "@google/gemini-cli"

    private let provider: GeminiProvider
    private let runner: GuidedInstallRunner

    // MARK: - Internal state machine

    private enum ActivePhase {
        case none
        /// Waiting for user to confirm before installing a prerequisite or the CLI itself.
        case confirmingInstall(PrerequisiteKind)
        /// Installing a prerequisite (Homebrew, Node.js).
        case installingDependency(name: String, progress: Double?)
        /// Installing the primary Gemini CLI.
        case installingCLI(progress: Double?)
        /// `gemini` subprocess is running; waiting for the [Y/n] confirm prompt.
        case awaitingUserConfirm(message: String)
        /// User confirmed; waiting for OAuth browser flow to complete.
        case awaitingOAuth(code: String?)
    }

    private enum PrerequisiteKind {
        case homebrew, node, geminiCLI
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

    /// Closure for writing to the running subprocess's stdin. Captured from
    /// the runner's `RunCLIHandle` after launch, cleared when the process
    /// exits or is cancelled.
    private var pendingStdinWrite: (@Sendable (String) -> Void)?

    /// Substring Gemini prints in its TTY-interactive confirm prompt.
    private static let geminiConfirmPromptMarker = "Do you want to continue?"

    /// Copy shown in Tokenomics' confirm pill (`.awaitingUserConfirm`) — rephrases
    /// gemini's terminal prompt for a GUI audience.
    private static let confirmDisplayMessage =
        "Tokenomics will open Google's sign-in page in your browser to connect Gemini. Continue?"

    // MARK: - Init

    init(provider: GeminiProvider = GeminiProvider()) {
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
        case .awaitingUserConfirm(let message):
            return .awaitingUserConfirm(message: message)
        case .awaitingOAuth(let code):
            // Peek at the provider — oauth_creds.json may have just appeared.
            let state = await provider.checkConnection()
            if case .connected(let plan) = state {
                activePhase = .none
                return .connected(plan: plan)
            }
            return .awaitingOAuth(code: code)
        case .none:
            break
        }

        let state = await provider.checkConnection()
        switch state {
        case .connected(let plan):
            return .connected(plan: plan)
        case .notInstalled:
            // Land on the prereq checklist, not the misleading "Sign in with
            // Google" CTA. Kick off the chain async — by the next 1.5s poll
            // tick activePhase will be `.confirmingInstall(.homebrew)` (or
            // whichever prereq is missing first) and the .confirmingInstall
            // case at the top of this function will return the right step.
            if !didStartDetection {
                didStartDetection = true
                Task { await self.startPrerequisiteChain() }
            }
            return .detecting
        case .installedNoAuth, .authExpired, .needsKeychainAccess:
            // Prereqs are all there — only sign-in remains. Still show the
            // "Checking your Mac" interstitial once so the user gets the
            // same coherent flow regardless of what was already installed
            // (Bug B). didStartDetection serves double duty: it prevents
            // the install chain from re-spawning AND prevents this
            // interstitial from looping.
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
        case .awaitingUserConfirm:
            // User tapped "Open browser to sign in" — answer gemini's [Y/n] prompt.
            activePhase = .awaitingOAuth(code: nil)
            pendingStdinWrite?("y\n")
            return
        case .awaitingOAuth:
            // User tapped "Reopen browser" — re-launch the CLI.
            await launchLogin()
            return
        case .none:
            break
        default:
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
        pendingStdinWrite = nil
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
        case .geminiCLI:
            await installCLI()
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
        if SystemPrerequisiteDetector.nodePath() == nil {
            activePhase = .confirmingInstall(.node)
            return
        }
        if geminiBinaryURL() == nil {
            activePhase = .confirmingInstall(.geminiCLI)
            return
        }
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
            Self.log.error("npm not found — cannot install Gemini CLI")
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
                    Self.log.info("Gemini CLI installed successfully")
                    await launchLogin()
                    return
                case .failed(let reason):
                    Self.log.error("Gemini CLI install failed: \(reason)")
                    activePhase = .none
                    failedState = classifyNpmFailure(reason)
                }
            }
        } catch {
            Self.log.error("Gemini CLI install error: \(error.localizedDescription)")
            activePhase = .none
            failedState = .cliInstallFailed(error.localizedDescription)
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
        // AppleScript parser errors ("A unknown token can't go after this …")
        // are bugs in Tokenomics, not anything the user can fix. Log the raw
        // text and surface a generic message so users don't see internal
        // gibberish.
        if isLikelyTechnicalError(lower) {
            Self.log.error("Suppressing technical Homebrew error from UI: \(reason, privacy: .public)")
            return .cliInstallFailed("")
        }
        return .cliInstallFailed(reason)
    }

    /// Heuristic: if the error string smells like a parser/syntax/internal
    /// error rather than something a user could recognize and act on, treat
    /// it as a generic install failure.
    private func isLikelyTechnicalError(_ lowercaseReason: String) -> Bool {
        let technicalMarkers = [
            "unknown token", "syntax error", "expected", "applescript",
            "osascript", "nsapplescripterror", "errosacanttellwhat"
        ]
        return technicalMarkers.contains(where: lowercaseReason.contains)
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

    /// Resolves the gemini binary — checks system paths then the Tokenomics per-user npm prefix.
    private func geminiBinaryURL() -> URL? {
        let systemPaths = [
            "/opt/homebrew/bin/gemini",
            "/usr/local/bin/gemini",
            "\(NSHomeDirectory())/.local/bin/gemini",
        ]
        let fm = FileManager.default
        for path in systemPaths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return SystemPrerequisiteDetector.tokenomicsNpmBinPath("gemini")
    }

    private func launchLogin() async {
        guard let binary = geminiBinaryURL() else {
            Self.log.error("gemini binary not found — cannot launch login")
            activePhase = .none
            return
        }

        // ~/.gemini/settings.json must declare an auth method or the CLI exits immediately.
        ensureGeminiAuthSettings()

        // Start in awaitingOAuth — we'll park in awaitingUserConfirm when we see
        // gemini's [Y/n] prompt so the user explicitly approves opening their browser.
        activePhase = .awaitingOAuth(code: nil)

        do {
            let handle = try await runner.runCommand(executable: binary, args: [])
            pendingStdinWrite = handle.writeStdin

            for await event in handle.events {
                switch event {
                case .stdout(let line):
                    Self.log.debug("[gemini stdout] \(line)")
                    if line.contains(Self.geminiConfirmPromptMarker) {
                        if case .awaitingUserConfirm = activePhase { break }
                        activePhase = .awaitingUserConfirm(message: Self.confirmDisplayMessage)
                    }
                case .stderr(let line):
                    Self.log.debug("[gemini stderr] \(line)")
                case .deviceCode:
                    // Not expected for gemini — it opens the browser itself.
                    break
                case .exited(let code):
                    Self.log.info("gemini exited with code \(code)")
                    pendingStdinWrite = nil
                    // Don't clear phase — let the polling loop detect oauth_creds.json.
                }
            }
        } catch {
            Self.log.error("gemini login error: \(error.localizedDescription)")
            activePhase = .none
            pendingStdinWrite = nil
        }
    }

    /// Writes the minimum settings.json needed for `gemini` to attempt OAuth
    /// when launched without a TTY. Preserves any existing keys the user may
    /// already have set; only adds `security.auth.selectedType` if absent.
    private func ensureGeminiAuthSettings() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".gemini")
        let file = dir.appendingPathComponent("settings.json")
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Self.log.error("Failed to create ~/.gemini: \(error.localizedDescription)")
            return
        }

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: file),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        }

        var security = root["security"] as? [String: Any] ?? [:]
        var auth = security["auth"] as? [String: Any] ?? [:]
        let existing = auth["selectedType"] as? String
        if existing == nil || existing?.isEmpty == true {
            auth["selectedType"] = "oauth-personal"
            security["auth"] = auth
            root["security"] = security

            do {
                let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
                try data.write(to: file, options: [.atomic])
                Self.log.info("Wrote default oauth-personal auth method to \(file.path)")
            } catch {
                Self.log.error("Failed to write ~/.gemini/settings.json: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private func confirmStep(for kind: PrerequisiteKind) -> ConnectorStep {
        switch kind {
        case .homebrew:
            return .confirmingInstall(
                title: "Install Homebrew",
                body: "Tokenomics needs Homebrew to install Gemini. Homebrew is the standard Mac package manager — about 2 minutes to install.",
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
        case .geminiCLI:
            return .confirmingInstall(
                title: "Install Gemini CLI",
                body: "Tokenomics will install Google's command-line Gemini tool. About 30 seconds.",
                commandPreview: "npm install -g @google/gemini-cli",
                footnote: "Installed to ~/.tokenomics-cli — keeps Tokenomics' tools out of your global npm.",
                skipLabel: "Already have Gemini CLI? Skip this step"
            )
        }
    }

    private func classifyNpmFailure(_ reason: String) -> ConnectorError {
        if reason.hasPrefix("EACCES:") {
            let path = String(reason.dropFirst("EACCES:".count))
            return .permissionDenied(path: path)
        }
        return .cliInstallFailed(reason)
    }

    @MainActor
    private func openOnMain(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
