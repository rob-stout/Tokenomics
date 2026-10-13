import Foundation
import AppKit
import os

/// Guided connector for Anthropic's Claude Code.
///
/// Flow (Pattern B — "we start it, you finish it"):
///   1. `.detecting` — checks for Homebrew and the `claude` binary.
///   2. If Homebrew missing: `.confirmingInstall(.homebrew)` → install → re-detect.
///   3. If `claude` missing: `.confirmingInstall(.claudeCode)` → install via
///      `brew install --cask claude-code` → re-detect.
///   4. `.previewingSignIn` (Window 3) — numbered checklist of Claude Code's OAuth wizard.
///   5. `.previewingSetup` (Window 4) — folder + permissions steps, "Open Terminal" CTA.
///   6. When user taps "Open Terminal": launches Terminal with `claude` via AppleScript
///      and transitions to `.awaitingExternalAuth` (Window 5).
///   7. Polling loop re-calls `currentStep()` every 1.5s. When `ClaudeProvider`
///      reports `.connected`, the flow ends.
///
/// **Policy note:** Anthropic's OpenClaw policy prohibits third-party apps from
/// driving Claude's OAuth flow. Tokenomics installs the CLI and guides the user
/// to Anthropic's own wizard via Terminal — we do not intercept tokens or open
/// the OAuth URL ourselves.
///
/// **AppleScript note:** Launching Terminal via AppleScript triggers a macOS
/// Automation TCC prompt on first use. This is expected — it's the same prompt
/// any app gets when it tries to control another app via AppleScript. The user
/// sees it once per Tokenomics install.
actor ClaudeConnector: ProviderConnector {
    nonisolated let id: ProviderId = .claude
    nonisolated let pipelineKind: ConnectorPipelineKind = .multiStep

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ClaudeConnector")

    private let provider: ClaudeProvider
    private let runner: GuidedInstallRunner

    // MARK: - Internal state machine

    private enum ActivePhase {
        case none
        /// Waiting for explicit user consent before starting an install.
        case confirmingInstall(PrerequisiteKind)
        /// Running `brew install` for a dependency (Homebrew itself via its script).
        case installingDependency(name: String, progress: Double?)
        /// Running `brew install --cask claude-code`.
        case installingCLI(progress: Double?)
        /// Window 3 — numbered preview of Claude Code's sign-in wizard.
        case previewingSignIn
        /// Window 4 — folder + permissions steps; "Open Terminal" fires from here.
        case previewingSetup
        /// Window 5 — Terminal is open, polling for credentials file.
        case awaitingExternalAuth
    }

    private enum PrerequisiteKind {
        case homebrew, claudeCode
    }

    private var activePhase: ActivePhase = .none

    /// Have we shown the "Checking your Mac" intro yet this session?
    /// Used to display the DetectStep once before transitioning to the
    /// needsAction CTA, so the flow feels consistent regardless of
    /// whether Claude Code was already installed (Bug B).
    private var didStartDetection = false

    /// Set when the last check reported `.needsKeychainAccess`, so the confirm
    /// screen's button routes to the keychain request instead of the install chain.
    private var isAwaitingKeychainAccess = false

    /// The last "Allow Access" tap ended without access (user denied or cancelled).
    /// Without this the step would look unchanged and the tap would seem to do nothing.
    private var didDenyKeychainAccess = false

    /// Sign-in preview is for a user who already has Claude Code installed (expired
    /// session or unreadable keychain), so it shouldn't say "Finish installing".
    private var isReloginFlow = false

    // MARK: - Init

    init(provider: ClaudeProvider = ClaudeProvider()) {
        self.provider = provider
        self.runner = GuidedInstallRunner()
    }

    // MARK: - ProviderConnector

    func currentStep() async -> ConnectorStep {
        // Surface a typed failure immediately if one was recorded.
        if let failure = failedState {
            return .failed(failure)
        }

        switch activePhase {
        case .confirmingInstall(let kind):
            return confirmStep(for: kind)

        case .installingDependency(let name, let progress):
            return .installingDependency(name: name, progress: progress)

        case .installingCLI(let progress):
            return .installing(progress: progress)

        case .previewingSignIn:
            return .previewExternalSteps(
                headline: isReloginFlow ? "Sign in to Claude Code again" : "Finish installing Claude Code",
                body: isReloginFlow
                    ? "Claude Code needs you to sign in again before Tokenomics can read your usage. Walk through the steps Anthropic has laid out — we're here to guide you. Here's what's going to happen:"
                    : "We've started the install for Claude Code. You'll need to finish it by walking through the steps Anthropic has laid out — we're here to guide you. Here's what's going to happen:",
                groupLabel: "In Claude Code, you'll:",
                startingNumber: 1,
                items: [
                    "**Pick login method** — choose **Claude account with subscription** if you're on Pro / Max",
                    "**Sign in via browser**, paste the email code Anthropic sends",
                    "**Authorize** Claude Code to connect to your account",
                    "**Accept** Anthropic's security notes",
                ],
                primaryLabel: isReloginFlow ? "Open Terminal" : "Continue"
            )

        case .previewingSetup:
            return .previewExternalSteps(
                headline: "Setup",
                body: "After you sign in, Claude Code asks for two more things — a folder and macOS permissions. Finish those and you're done.",
                groupLabel: "In Claude Code, you'll:",
                startingNumber: 5,
                items: [
                    "**Pick a folder** Claude can access — create a **Projects** folder in your *Home folder* if you don't have one",
                    "**Grant macOS permissions** as Claude Code asks for them",
                ],
                primaryLabel: "Open Terminal",
                headsUp: "Heads up: Claude Code asks macOS for access to a bunch of folders during setup — Music, Photos, Downloads, Documents. Safe to decline anything outside your Projects folder. Claude works fine without them."
            )

        case .awaitingExternalAuth:
            // Peek at the provider — credentials may have just appeared.
            let state = await provider.checkConnection()
            if case .connected(let plan) = state {
                activePhase = .none
                return .connected(plan: plan)
            }
            // A Terminal (re)login rewrites the keychain item, so our read now needs
            // the user's approval. Leave the waiting screen for the Allow Access step.
            if case .needsKeychainAccess = state {
                activePhase = .none
                return keychainAccessStep()
            }
            return .awaitingExternalAuth(
                headline: "Confirm login",
                body: "We're waiting for your successful login. **You'll know you're done when you see Claude's chat prompt** — close Terminal then and come back here."
            )

        case .none:
            break
        }

        // No active phase — delegate to provider for terminal states.
        let state = await provider.checkConnection()
        // Reentrancy: a tap (skip, install) may have moved the phase while we awaited;
        // answer for the new phase instead of overwriting it with a stale verdict.
        guard case .none = activePhase else { return await currentStep() }
        isAwaitingKeychainAccess = false
        // A different state means the denial is history; clear its note.
        if case .needsKeychainAccess = state {
            // keep the note
        } else {
            didDenyKeychainAccess = false
        }
        switch state {
        case .connected(let plan):
            return .connected(plan: plan)
        case .needsKeychainAccess:
            // Claude Code is signed in; macOS just hasn't let us read it. Not the
            // Terminal sign-in path. The polling loop only re-checks silently —
            // the macOS dialog fires solely from the user's tap on "Allow Access"
            // (confirmInstall).
            return keychainAccessStep()
        case .notInstalled, .installedNoAuth, .authExpired:
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
        case .awaitingExternalAuth:
            // "Reopen browser" / re-trigger — just re-detect; the polling loop handles it.
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
        case .installedNoAuth:
            // Binary is present, skip installs, go straight to preview.
            activePhase = .previewingSignIn
        case .authExpired:
            isReloginFlow = true
            activePhase = .previewingSignIn
        case .needsKeychainAccess:
            // Nothing to do: the next tick shows the "Allow Access" step. The macOS
            // dialog must only come from that button, never a sign-in-labelled CTA.
            return
        case .unavailable:
            return
        }
    }

    func cancel() async {
        await runner.cancel()
        activePhase = .none
        isAwaitingKeychainAccess = false
        didDenyKeychainAccess = false
        isReloginFlow = false
        failedState = nil
        didStartDetection = false
    }

    func clearFailure() async {
        failedState = nil
        activePhase = .none
        isAwaitingKeychainAccess = false
        didDenyKeychainAccess = false
        isReloginFlow = false
        // Re-arm so retry replays the detect intro.
        didStartDetection = false
    }

    func confirmInstall() async {
        // activePhase check: a stale flag must never hijack an install confirm step.
        if isAwaitingKeychainAccess, case .none = activePhase {
            await requestKeychainAccess()
            return
        }
        guard case .confirmingInstall(let kind) = activePhase else { return }
        switch kind {
        case .homebrew:
            await installHomebrew()
        case .claudeCode:
            await installClaudeCode()
        }
    }

    func skipInstall() async {
        failedState = nil
        if isAwaitingKeychainAccess {
            // "Sign in again" from the keychain step: the binary is already installed,
            // so skip the Homebrew/CLI prerequisite chain.
            isAwaitingKeychainAccess = false
            didDenyKeychainAccess = false
            isReloginFlow = true
            activePhase = .previewingSignIn
            return
        }
        activePhase = .none
        await startPrerequisiteChain()
    }

    /// Open Terminal with `claude` before transitioning so the hand-off is synchronous
    /// from the user's perspective. AppleScript blocks briefly — run off the main actor
    /// (we're already on the connector actor). Only advances if it didn't surface an error.
    private func openTerminalAndAwaitAuth() async {
        await openTerminalWithClaude()
        if failedState == nil {
            activePhase = .awaitingExternalAuth
        }
    }

    /// Called when the user taps the primary button on a `.previewExternalSteps` screen.
    /// Advances Window 3 → Window 4, or Window 4 → opens Terminal + Window 5.
    func advancePreview() async {
        switch activePhase {
        case .previewingSignIn:
            // A re-login already did first-run setup (folder, macOS permissions), so skip
            // that preview and go straight to Terminal.
            if isReloginFlow {
                await openTerminalAndAwaitAuth()
            } else {
                activePhase = .previewingSetup
            }

        case .previewingSetup:
            await openTerminalAndAwaitAuth()

        default:
            break
        }
    }

    /// The "Allow Access" confirm step. Also arms `isAwaitingKeychainAccess` so the
    /// button routes to the keychain request rather than the install chain.
    private func keychainAccessStep() -> ConnectorStep {
        isAwaitingKeychainAccess = true
        return .confirmingInstall(
            title: "Allow keychain access",
            body: "Tokenomics needs permission to read your Claude Code sign-in. macOS may ask twice. Enter your Mac password and choose \"Always Allow\" each time."
                + (didDenyKeychainAccess ? "\n\nmacOS didn't allow access. Try again." : ""),
            skipLabel: "Signed out of Claude Code? Sign in again",
            primaryLabel: "Allow Access",
            signInFramed: true
        )
    }

    /// The one place onboarding triggers the macOS keychain dialog. The next poll
    /// tick re-checks the connection, which now hits the shared cache.
    private func requestKeychainAccess() async {
        switch await ClaudeCredentialStore.shared.requestAccess() {
        case .needsAuthorization:
            didDenyKeychainAccess = true
        case .found, .notFound, .staleToken:
            // A stale token isn't a denial: the next tick routes to the re-login path.
            didDenyKeychainAccess = false
        }
    }

    // MARK: - Prerequisite chain

    private func startPrerequisiteChain() async {
        if SystemPrerequisiteDetector.homebrewPath() == nil {
            activePhase = .confirmingInstall(.homebrew)
            return
        }
        if claudeBinaryURL() == nil {
            activePhase = .confirmingInstall(.claudeCode)
            return
        }
        // Both present — advance to sign-in preview.
        activePhase = .previewingSignIn
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

    private func installClaudeCode() async {
        guard let brewPath = SystemPrerequisiteDetector.homebrewPath() else {
            Self.log.error("brew not found — cannot install Claude Code cask")
            activePhase = .none
            failedState = .missingPrerequisite("Homebrew")
            return
        }
        activePhase = .installingCLI(progress: nil)
        do {
            let events = try await runner.installViaHomebrew(
                brewPath: brewPath,
                formula: "claude-code",
                isCask: true
            )
            for await event in events {
                switch event {
                case .progress(let p):
                    activePhase = .installingCLI(progress: p)
                case .log(let line):
                    Self.log.debug("[claude-code install] \(line)")
                case .completed:
                    Self.log.info("Claude Code installed successfully via Homebrew cask")
                    isReloginFlow = false
                    activePhase = .previewingSignIn
                    return
                case .failed(let reason):
                    Self.log.error("Claude Code install failed: \(reason)")
                    activePhase = .none
                    failedState = classifyCaskFailure(reason)
                }
            }
        } catch {
            Self.log.error("Claude Code install error: \(error.localizedDescription)")
            activePhase = .none
            failedState = .cliInstallFailed(error.localizedDescription)
        }
    }

    // MARK: - Failure classification

    /// Maps a raw runner failure string to the most specific `ConnectorError`.
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

    private func classifyCaskFailure(_ reason: String) -> ConnectorError {
        if reason.hasPrefix("EACCES:") {
            let path = String(reason.dropFirst("EACCES:".count))
            return .permissionDenied(path: path)
        }
        let lower = reason.lowercased()
        if lower.contains("network") || lower.contains("curl") || lower.contains("connection refused") {
            return .homebrewNotReachable
        }
        return .caskInstallFailed(reason)
    }

    // MARK: - Binary detection

    /// Resolves the `claude` binary. Covers the Homebrew cask symlink
    /// (`/opt/homebrew/bin/claude`), the legacy Intel path, and a user-local bin.
    ///
    /// The Homebrew cask `claude-code` installs the binary to
    /// `/opt/homebrew/bin/claude` on Apple Silicon (symlinked from the cask's
    /// actual prefix). `ClaudeProvider.isClaudeCodeInstalled()` checks the same
    /// set of paths — keep them in sync if either changes.
    private func claudeBinaryURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.claude/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - Terminal handoff

    /// Opens Terminal.app and runs `claude` in a new window.
    ///
    /// Uses AppleScript because it's the simplest way to launch a specific command
    /// in a visible Terminal window without managing PTYs ourselves. The TCC
    /// Automation dialog appears the first time — this is expected macOS behaviour
    /// for any app that controls Terminal via AppleScript.
    ///
    /// If macOS denies the Automation permission (error -1743 or a message containing
    /// "not authorized to send Apple events"), surfaces `.failed(.automationPermissionDenied)`
    /// instead of silently swallowing the error.
    private func openTerminalWithClaude() async {
        let script = """
        tell application "Terminal"
            do script "claude"
            activate
        end tell
        """
        // AppleScript execution can block; run it in a detached task to avoid
        // holding the connector actor for the TCC prompt duration.
        let denied = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                appleScript?.executeAndReturnError(&error)
                if let err = error {
                    Self.log.error("AppleScript Terminal launch error: \(err)")
                    let code = err[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = (err[NSAppleScript.errorMessage] as? String ?? "").lowercased()
                    let isPermissionDenied = code == -1743
                        || message.contains("not authorized")
                        || message.contains("automation")
                    continuation.resume(returning: isPermissionDenied)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }

        if denied {
            activePhase = .none
            failedState = .automationPermissionDenied
        }
    }

    // MARK: - Error state

    /// When set, `currentStep()` returns `.failed` immediately regardless of `activePhase`.
    /// Cleared by the user tapping the recovery action (triggers a re-detect via
    /// `ConnectorViewModel.tappedRecovery()`).
    private var failedState: ConnectorError?

    // MARK: - Confirm step copy (mockup-exact)

    private func confirmStep(for kind: PrerequisiteKind) -> ConnectorStep {
        switch kind {
        case .homebrew:
            return .confirmingInstall(
                title: "Install Homebrew",
                body: "Tokenomics needs Homebrew to install Claude Code. Homebrew is the standard Mac package manager — about 2 minutes to install.",
                commandPreview: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
                footnote: "We'll open Terminal and install Homebrew with your permission. You'll be asked for your password once. This is Homebrew's official installer, straight from brew.sh.",
                skipLabel: "Already have Homebrew? Skip this step"
            )
        case .claudeCode:
            return .confirmingInstall(
                title: "Install Claude Code",
                body: "Now we'll install Claude Code using Homebrew. About 1 minute, no extra permissions needed.",
                commandPreview: "brew install --cask claude-code",
                footnote: "We'll run this in the same Terminal window. This is Anthropic's official Mac install — same command on claude.com's setup docs. Tokenomics doesn't add anything; we just run it for you.",
                skipLabel: "Already have Claude Code? Skip this step"
            )
        }
    }
}
