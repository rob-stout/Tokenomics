import Foundation
import AppKit
import os

/// Guided connector for Anthropic's Claude Code.
///
/// Flow (Pattern B — "we start it, you finish it"):
///   1. `.detecting` — checks for the `claude` binary.
///   2. If `claude` missing: `.confirmingInstall` → install via Anthropic's
///      native installer (`curl -fsSL https://claude.ai/install.sh | bash`).
///      No Homebrew and no admin prompt — it installs under `$HOME`.
///   3. `.previewingSignIn` (Window 3) — numbered checklist of Claude Code's OAuth wizard.
///   4. `.previewingSetup` (Window 4) — folder + permissions steps, "Open Terminal" CTA.
///   5. When user taps "Open Terminal": launches Terminal with `claude` via AppleScript
///      and transitions to `.awaitingExternalAuth` (Window 5).
///   6. Polling loop re-calls `currentStep()` every 1.5s. When `ClaudeProvider`
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
        /// Waiting for explicit user consent before installing Claude Code.
        case confirmingInstall
        /// Running Anthropic's native installer.
        case installingCLI(progress: Double?)
        /// Window 3 — numbered preview of Claude Code's sign-in wizard.
        case previewingSignIn
        /// Window 4 — folder + permissions steps; "Open Terminal" fires from here.
        case previewingSetup
        /// Window 5 — Terminal is open, polling for credentials file.
        case awaitingExternalAuth
    }

    private var activePhase: ActivePhase = .none

    /// Have we shown the "Checking your Mac" intro yet this session?
    /// Used to display the DetectStep once before transitioning to the
    /// needsAction CTA, so the flow feels consistent regardless of
    /// whether Claude Code was already installed (Bug B).
    private var didStartDetection = false

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
        case .confirmingInstall:
            return confirmStep()

        case .installingCLI(let progress):
            return .installing(progress: progress)

        case .previewingSignIn:
            return .previewExternalSteps(
                headline: "Finish installing Claude Code",
                body: "We've started the install for Claude Code. You'll need to finish it by walking through the steps Anthropic has laid out — we're here to guide you. Here's what's going to happen:",
                groupLabel: "In Claude Code, you'll:",
                startingNumber: 1,
                items: [
                    "**Pick login method** — choose **Claude account with subscription** if you're on Pro / Max",
                    "**Sign in via browser**, paste the email code Anthropic sends",
                    "**Authorize** Claude Code to connect to your account",
                    "**Accept** Anthropic's security notes",
                ],
                primaryLabel: "Continue"
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
            return .awaitingExternalAuth(
                headline: "Confirm login",
                body: "We're waiting for your successful login. **You'll know you're done when you see Claude's chat prompt** — close Terminal then and come back here."
            )

        case .none:
            break
        }

        // No active phase — delegate to provider for terminal states.
        let state = await provider.checkConnection()
        switch state {
        case .connected(let plan):
            return .connected(plan: plan)
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
        case .installedNoAuth, .authExpired:
            // Binary is present, skip installs, go straight to preview.
            activePhase = .previewingSignIn
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
        guard case .confirmingInstall = activePhase else { return }
        await installClaudeCode()
    }

    /// "Already have Claude Code?" — trust the user and go to sign-in. Re-running
    /// detection here would just land back on the same confirm screen when their
    /// install lives somewhere we don't look.
    func skipInstall() async {
        failedState = nil
        activePhase = .previewingSignIn
    }

    /// Called when the user taps the primary button on a `.previewExternalSteps` screen.
    /// Advances Window 3 → Window 4, or Window 4 → opens Terminal + Window 5.
    func advancePreview() async {
        switch activePhase {
        case .previewingSignIn:
            activePhase = .previewingSetup

        case .previewingSetup:
            // Open Terminal with `claude` before transitioning so the hand-off is
            // synchronous from the user's perspective. AppleScript blocks briefly —
            // run it off the main actor (we're already on the connector actor).
            await openTerminalWithClaude()
            // Only advance if openTerminalWithClaude didn't surface an error.
            if failedState == nil {
                activePhase = .awaitingExternalAuth
            }

        default:
            break
        }
    }

    // MARK: - Prerequisite chain

    private func startPrerequisiteChain() async {
        if SystemPrerequisiteDetector.claudePath() == nil {
            activePhase = .confirmingInstall
            return
        }
        activePhase = .previewingSignIn
    }

    // MARK: - Install step

    private func installClaudeCode() async {
        activePhase = .installingCLI(progress: nil)
        do {
            let events = try await runner.installClaudeCodeNative()
            for await event in events {
                switch event {
                case .progress(let p):
                    activePhase = .installingCLI(progress: p)
                case .log(let line):
                    Self.log.debug("[claude install] \(line)")
                case .completed:
                    // The installer can exit 0 without leaving a binary behind
                    // (e.g. a partial download) — confirm before moving on.
                    guard SystemPrerequisiteDetector.claudePath() != nil else {
                        Self.log.error("Native installer exited 0 but no claude binary was found")
                        activePhase = .none
                        failedState = .missingPrerequisite("Claude Code")
                        return
                    }
                    Self.log.info("Claude Code installed successfully via native installer")
                    addLocalBinToShellPath()
                    activePhase = .previewingSignIn
                    return
                case .failed(let reason):
                    Self.log.error("Claude Code install failed: \(reason)")
                    activePhase = .none
                    failedState = classifyInstallFailure(reason)
                }
            }
        } catch {
            Self.log.error("Claude Code install error: \(error.localizedDescription)")
            activePhase = .none
            failedState = .cliInstallFailed(error.localizedDescription)
        }
    }

    // MARK: - Shell PATH

    /// Adds `~/.local/bin` to the user's login-shell PATH so `claude` works when
    /// they type it in Terminal later. Anthropic's installer puts the binary there
    /// but only *prints* a note about PATH — it doesn't edit shell files.
    ///
    /// Best-effort and idempotent: skipped if the shell file already mentions
    /// `.local/bin`. Writes `~/.zprofile` for zsh (the macOS default) or
    /// `~/.bash_profile` for bash; other shells are left alone.
    private func addLocalBinToShellPath() {
        let home = NSHomeDirectory()
        let loginShell = getpwuid(getuid()).map { String(cString: $0.pointee.pw_shell) } ?? "/bin/zsh"
        let fileName: String
        switch URL(fileURLWithPath: loginShell).lastPathComponent {
        case "zsh": fileName = ".zprofile"
        case "bash": fileName = ".bash_profile"
        default:
            Self.log.info("Login shell \(loginShell) not handled — leaving PATH alone")
            return
        }
        let profile = URL(fileURLWithPath: home).appendingPathComponent(fileName)
        let existing = (try? String(contentsOf: profile, encoding: .utf8)) ?? ""
        guard !existing.contains(".local/bin") else { return }

        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let addition = separator + """

        # Added by Tokenomics — Claude Code's installer puts `claude` here.
        export PATH="$HOME/.local/bin:$PATH"

        """
        do {
            if FileManager.default.fileExists(atPath: profile.path) {
                let handle = try FileHandle(forWritingTo: profile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(addition.utf8))
            } else {
                try addition.write(to: profile, atomically: true, encoding: .utf8)
            }
            Self.log.info("Added ~/.local/bin to PATH in ~/\(fileName)")
        } catch {
            Self.log.error("Couldn't update ~/\(fileName): \(error.localizedDescription)")
        }
    }

    // MARK: - Failure classification

    /// Maps the installer's last stderr line to a user-facing error. Network and
    /// region failures get plain copy; anything else passes the installer's own
    /// message through (it's written for humans).
    private func classifyInstallFailure(_ reason: String) -> ConnectorError {
        if reason.hasPrefix("EACCES:") {
            let path = String(reason.dropFirst("EACCES:".count))
            return .permissionDenied(path: path)
        }
        let lower = reason.lowercased()
        if lower.contains("could not resolve host") || lower.contains("connection refused")
            || lower.contains("curl") || lower.contains("download failed") {
            return .cliInstallFailed("Claude Code couldn't download. Check your internet connection and try again.")
        }
        return .cliInstallFailed(reason)
    }

    // MARK: - Terminal handoff

    /// Opens Terminal.app and runs `claude` in a new window.
    ///
    /// Launches by full path: Anthropic's native installer puts `claude` in
    /// `~/.local/bin`, which is usually not on the user's shell PATH yet, so a
    /// bare `claude` would fail with "command not found". Falls back to the bare
    /// name only when we can't find the binary (user tapped "Already have it").
    ///
    /// If macOS denies the Automation permission, surfaces
    /// `.failed(.automationPermissionDenied)` instead of silently swallowing it.
    private func openTerminalWithClaude() async {
        let command = SystemPrerequisiteDetector.claudePath()
            .map { GuidedInstallRunner.shellQuoted($0.path) } ?? "claude"
        switch await GuidedInstallRunner.openInTerminal(command) {
        case .opened:
            break
        case .automationDenied:
            activePhase = .none
            failedState = .automationPermissionDenied
        case .failed(let message):
            // Matches prior behavior: a non-permission launch error doesn't block
            // the flow — the user can still open Terminal and run `claude` themselves.
            Self.log.error("Terminal launch failed: \(message)")
        }
    }

    // MARK: - Error state

    /// When set, `currentStep()` returns `.failed` immediately regardless of `activePhase`.
    /// Cleared by the user tapping the recovery action (triggers a re-detect via
    /// `ConnectorViewModel.tappedRecovery()`).
    private var failedState: ConnectorError?

    // MARK: - Confirm step copy

    private func confirmStep() -> ConnectorStep {
        .confirmingInstall(
            title: "Install Claude Code",
            body: "Tokenomics will install Claude Code for you. About 1 minute, no password needed.",
            commandPreview: "curl -fsSL https://claude.ai/install.sh | bash",
            footnote: "This is Anthropic's official installer, straight from claude.com's setup docs. It installs into your home folder — Tokenomics doesn't add anything; we just run it for you.",
            skipLabel: "Already have Claude Code? Skip this step"
        )
    }
}
