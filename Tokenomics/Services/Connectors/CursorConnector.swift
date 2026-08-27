import Foundation
import AppKit
import os

/// Guided-mode connector for Cursor.
///
/// Flow (Pattern D — "download an app, sign into it, wait for both"):
///   1. `currentStep()` checks for the Cursor.app bundle via NSWorkspace.
///   2. If not found + `.none` phase → `.needsAction`.
///   3. `performPrimaryAction()` from `.needsAction` → `.confirmingInstall`.
///   4. User taps "Open cursor.com" → `confirmInstall()` opens the browser
///      and transitions to `.waitingForBundle`.
///   5. Polling loop re-calls `currentStep()` every 1.5s. When the Cursor
///      bundle is detected AND the auth file exists, the flow is done.
///
/// Cursor is unique: Tokenomics does not manage the install. We hand off
/// to cursor.com and poll for two signals — the app bundle *and* the user's
/// sign-in (the JWT only appears in Cursor's local config after first launch).
///
/// A second, shorter path handles the common case where Cursor is already
/// installed but the user is signed out (`.installedNoAuth` on first
/// detection): rather than reusing the install framing above — which used to
/// send users to cursor.com's downloads page even though nothing needs
/// downloading — this shows a sign-in-framed confirm screen that opens the
/// already-installed app, then polls for sign-in only.
actor CursorConnector: ProviderConnector {
    nonisolated let id: ProviderId = .cursor
    nonisolated let pipelineKind: ConnectorPipelineKind = .multiStep

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CursorConnector")
    private static let downloadURL = URL(string: "https://cursor.com/downloads")!

    private let provider: CursorProvider

    // MARK: - Internal state machine

    private enum ActivePhase {
        /// No action in progress — detect from scratch.
        case none
        /// Showing the "Install Cursor" confirm screen before opening cursor.com.
        case confirmingInstall
        /// Browser is open; polling for the app bundle + sign-in to appear.
        case waitingForBundle
        /// Cursor is already installed but signed out — showing the "Sign in
        /// to Cursor" confirm screen before opening the installed app.
        case confirmingSignIn
        /// Cursor app was opened (or was already installed); polling for
        /// sign-in only — the bundle is already confirmed present.
        case waitingForSignIn
    }

    private var activePhase: ActivePhase = .none

    // MARK: - Init

    init(provider: CursorProvider = CursorProvider()) {
        self.provider = provider
    }

    // MARK: - ProviderConnector

    nonisolated var stepperLabels: (step1: String, step2: String, step3: String, step4: String) {
        ("Checking tools", "Installing Cursor", "Signing in", "Connection check")
    }

    func currentStep() async -> ConnectorStep {
        switch activePhase {
        case .confirmingInstall:
            return Self.installConfirmStep

        case .waitingForBundle:
            // Peek at provider — Cursor may have just been installed and signed in.
            let state = await provider.checkConnection()
            switch state {
            case .connected(let plan):
                activePhase = .none
                return .connected(plan: plan)
            case .installedNoAuth:
                // The bundle appeared while auth is still missing. The user is
                // presumably already looking at Cursor (first launch commonly
                // prompts sign-in itself) — skip re-confirming and go straight
                // to the sign-in wait rather than staying on "waiting to
                // install" forever.
                activePhase = .waitingForSignIn
                return Self.signInWaitStep
            default:
                return .waitingForExternalApp
            }

        case .confirmingSignIn:
            return Self.signInConfirmStep

        case .waitingForSignIn:
            let state = await provider.checkConnection()
            if case .connected(let plan) = state {
                activePhase = .none
                return .connected(plan: plan)
            }
            return Self.signInWaitStep

        case .none:
            break
        }

        // No active phase — delegate to provider.
        let state = await provider.checkConnection()
        switch state {
        case .connected(let plan):
            return .connected(plan: plan)
        case .notInstalled:
            return .needsAction
        case .installedNoAuth:
            // App bundle is present but sign-in hasn't completed. Surface the
            // sign-in confirm screen — installing is not the missing step here.
            activePhase = .confirmingSignIn
            return Self.signInConfirmStep
        case .authExpired:
            return .needsAction
        case .unavailable(let reason):
            return .failed(.unknown(reason))
        }
    }

    func performPrimaryAction() async {
        switch activePhase {
        case .waitingForBundle, .waitingForSignIn:
            // "Check now" — just re-detect; polling loop handles it.
            return
        case .none:
            // Transition to confirm screen before opening the browser.
            activePhase = .confirmingInstall
        default:
            return
        }
    }

    func confirmInstall() async {
        switch activePhase {
        case .confirmingInstall:
            // Open cursor.com in the default browser.
            await openOnMain(Self.downloadURL)
            activePhase = .waitingForBundle
        case .confirmingSignIn:
            // Cursor is already installed — launch it directly rather than
            // sending the user to the downloads page.
            await openCursorApp()
            activePhase = .waitingForSignIn
        default:
            return
        }
    }

    func skipInstall() async {
        // "Already installed? Check now" / "I've signed in — check now" —
        // re-detect from scratch either way.
        activePhase = .none
    }

    func cancel() async {
        activePhase = .none
    }

    func clearFailure() async {
        activePhase = .none
    }

    // MARK: - Step copy

    private static let installConfirmStep: ConnectorStep = .confirmingInstall(
        title: "Install Cursor",
        body: "Cursor is a separate Mac app. Once it's installed and you've signed in to it once, Tokenomics will pick up your usage automatically.",
        commandPreview: "https://cursor.com/downloads",
        footnote: "cursor.com/downloads is Cursor's official download page. We're just opening it for you — same place you'd land if you searched \"Cursor download.\"",
        skipLabel: "Already installed Cursor? Check now"
    )

    private static let signInConfirmStep: ConnectorStep = .confirmingInstall(
        title: "Sign in to Cursor",
        body: "Cursor is already installed — you just need to sign in inside the app once. Tokenomics will pick up your usage automatically after that.",
        commandPreview: nil,
        footnote: "We'll open the Cursor app for you. Look for its sign-in screen — nothing else to install.",
        skipLabel: "I've signed in — check now",
        primaryLabel: "Open Cursor",
        // Installing is already done here — highlight step 3 ("Signing in")
        // on the stepper instead of step 2 ("Installing Cursor").
        signInFramed: true
    )

    private static let signInWaitStep: ConnectorStep = .awaitingExternalAuth(
        headline: "Waiting for you to sign in to Cursor",
        body: "Sign in inside the Cursor app — we'll detect it automatically.",
        // Overrides AwaitExternalAuthView's Claude-specific default copy
        // ("Watching ~/.claude…") and hides its Terminal illustration —
        // Cursor's sign-in happens inside the app's own window, not a shell.
        caption: "Watching for Cursor's sign-in — sign in inside the Cursor app and we'll pick it up.",
        showsTerminalArt: false
    )

    // MARK: - Helpers

    @MainActor
    private func openOnMain(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Launches the installed Cursor app via Launch Services. Falls back to
    /// the standard /Applications path if Launch Services doesn't resolve
    /// the bundle ID for some reason (e.g. a stale LS database).
    @MainActor
    private func openCursorApp() async {
        let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CursorProvider.bundleIdentifier)
            ?? URL(fileURLWithPath: "/Applications/Cursor.app")
        do {
            try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            Self.log.error("Failed to open Cursor.app: \(error.localizedDescription, privacy: .public)")
        }
    }
}
