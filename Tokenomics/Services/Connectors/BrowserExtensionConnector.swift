import Foundation
import AppKit
import os

// MARK: - ConnectorClock

/// Minimal sleep abstraction. The real implementation forwards to `Task.sleep`;
/// tests substitute a stub that records calls without waiting real wall time.
protocol ConnectorClock: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

/// Production clock — wraps `Task.sleep(nanoseconds:)`.
struct SystemConnectorClock: ConnectorClock {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - URLOpener

/// Wraps URL-open so tests can record calls without launching a real browser.
protocol URLOpener: Sendable {
    @MainActor func open(_ url: URL)
}

/// Production opener — delegates to NSWorkspace.
struct WorkspaceURLOpener: URLOpener {
    @MainActor func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - DefaultBrowserDetector

/// Detects the user's default browser so the connector can route to the right
/// install destination. Safari can only get the extension via the Mac App
/// Store companion app — every other browser uses the Chrome Web Store.
protocol DefaultBrowserDetector: Sendable {
    @MainActor func isSafariDefault() -> Bool
}

/// Production detector — asks Launch Services which app would open an https
/// URL (the standard way to read the default browser) and checks its bundle
/// identifier against Safari's.
struct WorkspaceDefaultBrowserDetector: DefaultBrowserDetector {
    @MainActor func isSafariDefault() -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://apple.com")!) else {
            return false
        }
        return Bundle(url: appURL)?.bundleIdentifier == "com.apple.Safari"
    }
}

// MARK: - BrowserExtensionConnector

/// Connector for the "Install the Tokenomics browser extension" step.
///
/// This connector has no `ProviderId` of its own — the browser extension is a
/// shared prerequisite for ALL web-companion providers (Claude.ai, ChatGPT,
/// Midjourney). It uses `.chatgpt` as its identifier only because the
/// `ProviderConnector` protocol requires a unique `ProviderId`; the ID is not
/// surfaced in any user-facing string.
///
/// Flow:
///   1. On appear — check `WebCompanionService.currentState().isFresh()`.
///      If fresh: emit `.connected(plan: "")` immediately (step already done).
///   2. If not fresh: surface `.needsAction` with "Open Chrome Web Store" CTA.
///      Tapping the CTA opens the store URL and starts polling every ~5s for
///      a fresh heartbeat.
///   3. If heartbeat arrives during polling: transition to `.connected`.
///   4. If user taps skip: transition to `.skipped`. Polling stops; the
///      orchestrator routes around this step.
///
/// The connector does NOT drive authentication — it only gates on whether the
/// extension is installed and has sent at least one heartbeat to the bridge.
actor BrowserExtensionConnector: ProviderConnector {

    // The extension is a shared prerequisite, not a per-provider service.
    // ProviderId.chatgpt is used as a stable placeholder because the protocol
    // requires a ProviderId and chatgpt is the primary web-companion provider.
    nonisolated let id: ProviderId = .chatgpt
    nonisolated let pipelineKind: ConnectorPipelineKind = .singleShot

    nonisolated var stepperLabels: (step1: String, step2: String, step3: String, step4: String) {
        ("Checking tools", "Install extension", "Connect", "Connection check")
    }

    // This flow installs the shared browser extension, which covers many web
    // providers — not just the placeholder `.chatgpt` id. Frame every screen
    // around the extension so the title/success don't misleadingly say "ChatGPT".
    nonisolated var flowDisplayName: String { "the browser extension" }
    nonisolated var successTitle: String { "The browser extension is connected." }
    nonisolated var successSubtitle: String { "Tokenomics is now reading your AI usage from the browser." }

    private static let log = Logger(
        subsystem: "com.robstout.tokenomics",
        category: "BrowserExtensionConnector"
    )

    /// Chrome Web Store URL for the Tokenomics extension.
    /// The dev-keypair extension ID is the stable identifier used in the
    /// NMH manifest's `allowed_origins`. The public listing URL uses the same ID.
    private static let webStoreURL = URL(
        string: "https://chromewebstore.google.com/detail/gcjaebikgcbccgbnbcimccflcgoeefio"
    )!

    /// App Store listing URL for "Tokenomics for Safari" — the sandboxed Mac
    /// App Store companion app that hosts the Safari Web Extension. Safari has
    /// no unpacked/dev-keypair install path (unlike Chrome), so it's the only
    /// destination for Safari users. Exposed (non-private) so Settings and
    /// About can link to the same destination without duplicating the URL.
    ///
    /// TODO: replace with the real App Store id once the "Tokenomics for
    /// Safari" listing exists, e.g.
    /// https://apps.apple.com/app/tokenomics-for-safari/idPLACEHOLDER
    /// Until then this resolves to the marketing site so the link never 404s.
    static let appStoreURL = URL(string: "https://trytokenomics.com")!

    /// Seconds since `updatedAt` that count as a live heartbeat.
    /// The extension sends heartbeats on every NMH round-trip (~60s); 5 minutes
    /// gives enough headroom for a browser restart or a slow first install.
    private static let freshnessTTL: TimeInterval = 300

    /// How long to wait between polls once the store has been opened.
    private static let pollInterval: TimeInterval = 5

    /// Shared privacy footnote — identical across the Chrome and Safari install
    /// steps, so it's defined once here.
    private static let installFootnote = "The extension reads only your usage counts — never your prompts, messages, or files. It runs locally and talks only to Tokenomics on your Mac."

    /// Which store the "install the extension" step should point at. Safari
    /// only ever gets the extension through its Mac App Store companion app;
    /// every other browser goes to the Chrome Web Store listing.
    private enum BrowserKind: Sendable {
        case safari
        case other
    }

    /// The "install the extension" step. Rendered with `ConfirmInstallStep`, which
    /// places the stepper on segment 2 ("Install extension") — the correct
    /// position while the extension is not yet installed. (The OAuth `.needsAction`
    /// path put it on segment 3 "Connect", which was wrong for an install.)
    /// No shell command, so the command card is hidden (`commandPreview: nil`).
    ///
    /// Copy branches by default browser: Safari frames the App Store companion
    /// app; every other browser keeps the original Chrome Web Store copy.
    private static func installStep(for browser: BrowserKind) -> ConnectorStep {
        switch browser {
        case .safari:
            return .confirmingInstall(
                title: "Add Tokenomics to Safari",
                body: "Tokenomics reads your web usage — ChatGPT, Gemini, and more — through a lightweight Safari extension from the App Store. Install it, switch it on in Safari, and come back; we'll detect it automatically.",
                commandPreview: nil,
                footnote: Self.installFootnote,
                skipLabel: "Skip for now",
                // The step title is a headline, not what the button does — the
                // CTA opens the App Store, so say that.
                primaryLabel: "Get it on the App Store"
            )
        case .other:
            return .confirmingInstall(
                title: "Install the browser extension",
                body: "Tokenomics reads your web usage — ChatGPT, Gemini, and more — through a lightweight browser extension. Install it and come back; we'll detect it automatically.",
                commandPreview: nil,
                footnote: Self.installFootnote,
                skipLabel: "Skip for now",
                // Same reasoning as the Safari branch — the CTA opens the
                // Chrome Web Store, so the button should say that.
                primaryLabel: "Open Chrome Web Store"
            )
        }
    }

    // MARK: - Dependencies

    private let webCompanion: any WebCompanionStateProvider
    private let clock: any ConnectorClock
    private let opener: any URLOpener
    private let browserDetector: any DefaultBrowserDetector

    // MARK: - Internal state machine

    private enum ActivePhase {
        /// No action in progress — run the freshness check.
        case none
        /// Store is open; polling for a fresh heartbeat.
        case polling
        /// User tapped skip.
        case skipped
    }

    private var activePhase: ActivePhase = .none

    /// Cached wall-clock reference so `isFresh` is always evaluated against
    /// the same "now" within a single `currentStep()` call.
    private var lastCheckedAt: Date = .distantPast

    /// Cached default-browser result. Computed once on first use — the user's
    /// default browser is not expected to change mid-flow, and this avoids a
    /// Launch Services round-trip on every ~1.5s poll tick.
    private var cachedBrowserKind: BrowserKind?

    // MARK: - Init

    init(
        webCompanion: any WebCompanionStateProvider,
        clock: any ConnectorClock = SystemConnectorClock(),
        opener: any URLOpener = WorkspaceURLOpener(),
        browserDetector: any DefaultBrowserDetector = WorkspaceDefaultBrowserDetector()
    ) {
        self.webCompanion = webCompanion
        self.clock = clock
        self.opener = opener
        self.browserDetector = browserDetector
    }

    // MARK: - ProviderConnector

    func currentStep() async -> ConnectorStep {
        switch activePhase {
        case .skipped:
            return .skipped

        case .polling:
            // Peek at the bridge — a fresh heartbeat means the extension connected.
            let state = await webCompanion.currentState()
            if state.isFresh(within: Self.freshnessTTL) {
                Self.log.info("Extension heartbeat received — marking connected")
                activePhase = .none
                return .connected(plan: "")
            }
            // Installed; now waiting for the extension to connect to Tokenomics.
            // This is stepper step 3 ("Connect") — a real "connecting" screen,
            // not the install step.
            return .awaitingExternalAuth(
                headline: "Connecting the extension",
                body: "Once the extension is installed, it connects to Tokenomics automatically — usually within a few seconds."
            )

        case .none:
            break
        }

        // Initial or post-cancel check: is the extension already connected?
        let state = await webCompanion.currentState()
        if state.isFresh(within: Self.freshnessTTL) {
            Self.log.info("Extension already connected — skipping install step")
            return .connected(plan: "")
        }

        return Self.installStep(for: await detectedBrowserKind())
    }

    /// Tapping the primary CTA ("Open Chrome Web Store" / "Get it on the App
    /// Store") opens the store URL and starts the polling phase. Subsequent
    /// taps while polling are no-ops — the polling loop is already watching
    /// for the heartbeat.
    func performPrimaryAction() async {
        await confirmInstall()
    }

    /// "Continue" on the install step (`ConfirmInstallStep`): open the install
    /// destination and begin polling the bridge for the extension's first
    /// heartbeat. Subsequent taps while polling are no-ops.
    func confirmInstall() async {
        guard activePhase == .none else {
            // Already polling or skipped — nothing to do.
            return
        }
        let browser = await detectedBrowserKind()
        let destinationURL = browser == .safari ? Self.appStoreURL : Self.webStoreURL
        await opener.open(destinationURL)
        Self.log.info("Opened install destination for \(browser == .safari ? "Safari" : "other browser"): \(destinationURL)")
        activePhase = .polling
        // Kick off the background poll loop so the connector drives forward
        // without relying solely on the VM's 1.5s general poll cadence.
        Task { await runPollLoop() }
    }

    /// "Skip for now" on the install step: mark skipped so the synthesis
    /// orchestrator advances to the next provider in the queue.
    func skipInstall() async {
        activePhase = .skipped
        Self.log.info("User skipped browser extension install step")
    }

    func cancel() async {
        activePhase = .none
    }

    func clearFailure() async {
        activePhase = .none
    }

    // MARK: - Skip

    /// Call when the user taps "Skip this step". Transitions to `.skipped`; the
    /// VM's polling loop picks it up and fires `onOutcome(.skipped)`.
    func skip() async {
        activePhase = .skipped
        Self.log.info("User skipped browser extension install step")
    }

    // MARK: - Private

    /// Background polling loop. Wakes every `pollInterval` seconds and checks
    /// whether the bridge has received a fresh heartbeat. Exits when the
    /// connector transitions out of `.polling` (connected, cancelled, or skipped).
    private func runPollLoop() async {
        while case .polling = activePhase {
            // Sleep first — we already did an immediate check in `currentStep()`.
            try? await clock.sleep(seconds: Self.pollInterval)

            guard case .polling = activePhase else { break }

            let state = await webCompanion.currentState()
            if state.isFresh(within: Self.freshnessTTL) {
                Self.log.info("Extension heartbeat received during poll loop")
                activePhase = .none
                // The VM's polling loop will call currentStep() and see .connected.
                break
            }
        }
    }

    /// Resolves and caches which install destination to use. See
    /// `cachedBrowserKind` for why this is cached rather than re-detected
    /// on every call.
    private func detectedBrowserKind() async -> BrowserKind {
        if let cachedBrowserKind {
            return cachedBrowserKind
        }
        let kind: BrowserKind = await browserDetector.isSafariDefault() ? .safari : .other
        cachedBrowserKind = kind
        return kind
    }
}
