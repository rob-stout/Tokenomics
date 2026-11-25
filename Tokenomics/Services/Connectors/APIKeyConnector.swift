import Foundation
import AppKit
import os

/// Guided-mode connector for API-key providers — Stability AI, Runway, ElevenLabs.
///
/// Flow (Pattern E — "get a key from the provider, paste it here"):
///   1. `currentStep()` checks Keychain via `APIKeyService`. If a key exists → `.connected`.
///   2. `performPrimaryAction()` from `.needsAction` → `.openProviderSite`.
///   3. User taps "Open [Provider]" → `confirmInstall()` opens the provider's key page
///      and transitions to `.pasteKey`.
///   4. User pastes their API key and taps "Save & connect".
///   5. `submitAPIKey(_:)` saves to Keychain → polling loop detects connection.
///
/// All three providers share the same shape — the per-provider URL is the only difference.
actor APIKeyConnector: ProviderConnector {
    nonisolated let id: ProviderId
    nonisolated let pipelineKind: ConnectorPipelineKind = .multiStep

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "APIKeyConnector")

    private let provider: any UsageProvider

    // MARK: - Internal state machine

    private enum ActivePhase {
        /// No action in progress — detect from scratch.
        case none
        /// Showing the "Open [Provider]" confirm screen before opening the browser.
        case openProviderSite
        /// Browser is open; waiting for user to paste their API key.
        case pasteKey
    }

    private var activePhase: ActivePhase = .none

    // MARK: - Per-provider URLs

    /// The URL that opens the provider's API key management page.
    private var providerKeyURL: URL {
        switch id {
        case .stableDiffusion:
            return URL(string: "https://platform.stability.ai/account/keys")!
        case .runway:
            return URL(string: "https://app.runwayml.com/account")!
        case .elevenlabs:
            return URL(string: "https://elevenlabs.io/app/settings/api-keys")!
        default:
            return id.setupGuideURL
        }
    }

    // MARK: - Stepper labels

    nonisolated var stepperLabels: (step1: String, step2: String, step3: String, step4: String) {
        ("Checking tools", "Get API key", "Paste key", "Connection check")
    }

    // MARK: - Init

    init(providerId: ProviderId, provider: any UsageProvider) {
        self.id = providerId
        self.provider = provider
    }

    // MARK: - ProviderConnector

    func currentStep() async -> ConnectorStep {
        switch activePhase {
        case .openProviderSite:
            return providerSiteStep()

        case .pasteKey:
            // Check if a key was already saved (e.g., user pasted + came back).
            if APIKeyService.read(for: id) != nil {
                let state = await provider.checkConnection()
                if case .connected(let plan) = state {
                    activePhase = .none
                    return .connected(plan: plan)
                }
            }
            return .pasteAPIKey(providerName: id.displayName, helpURL: providerKeyURL)

        case .none:
            break
        }

        // No active phase — check Keychain directly for the fast path.
        if APIKeyService.read(for: id) != nil {
            let state = await provider.checkConnection()
            switch state {
            case .connected(let plan):
                return .connected(plan: plan)
            case .unavailable(let reason):
                return .failed(.unknown(reason))
            default:
                break
            }
        }

        return .needsAction
    }

    func performPrimaryAction() async {
        switch activePhase {
        case .none:
            // Transition to the "Open Provider" confirm screen.
            activePhase = .openProviderSite
        case .pasteKey:
            // Primary tap from paste step — "Save & connect" is handled by submitAPIKey.
            // "Reopen browser" tapped from waiting state — re-open.
            await openOnMain(providerKeyURL)
        default:
            break
        }
    }

    func confirmInstall() async {
        guard case .openProviderSite = activePhase else { return }
        await openOnMain(providerKeyURL)
        activePhase = .pasteKey
    }

    func skipInstall() async {
        // "Already have a key? Skip" — go straight to paste step.
        activePhase = .pasteKey
    }

    func cancel() async {
        activePhase = .none
    }

    /// Back from the paste step should land on the "Open Provider" step,
    /// not all the way back at the chooser — the user is mid-flow and may
    /// need to re-read the instructions or re-open the provider's dashboard.
    func goBackOneStep() async {
        switch activePhase {
        case .pasteKey:
            activePhase = .openProviderSite
        case .openProviderSite:
            // First sub-step has no meaningful previous step; let the chooser
            // back-out handle this case via the connector's onBack closure.
            activePhase = .none
        case .none:
            break
        }
    }

    func clearFailure() async {
        activePhase = .none
    }

    func submitAPIKey(_ key: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        APIKeyService.save(trimmed, for: id)
        Self.log.info("API key saved for \(self.id.rawValue)")

        // Verify the key works immediately.
        let state = await provider.checkConnection()
        if case .connected = state {
            activePhase = .none
            return true
        }
        // Key saved but connection check failed — leave phase at .pasteKey
        // so the polling loop can re-try. Return true (save succeeded even
        // if the initial check wasn't instant).
        return true
    }

    // MARK: - Step copy

    private func providerSiteStep() -> ConnectorStep {
        switch id {
        case .stableDiffusion:
            return .openProviderSite(
                headline: "Get your Stability API key",
                body: "Tokenomics will open Stability's dashboard. Find your API keys under Account → API Keys — we recommend generating a new one so you can revoke it independently later.",
                ctaLabel: "Open Stability AI"
            )
        case .runway:
            return .openProviderSite(
                headline: "Get your Runway API key",
                body: "Tokenomics will open Runway's account page. Find or create your API key under Account settings.",
                ctaLabel: "Open Runway"
            )
        case .elevenlabs:
            return .openProviderSite(
                headline: "Get your ElevenLabs API key",
                body: "Tokenomics will open ElevenLabs' settings. Copy your API key from the API Keys section.",
                ctaLabel: "Open ElevenLabs"
            )
        default:
            return .openProviderSite(
                headline: "Get your API key",
                body: "Tokenomics needs an API key from \(id.displayName) to track your usage.",
                ctaLabel: "Open \(id.displayName)"
            )
        }
    }

    // MARK: - Helpers

    @MainActor
    private func openOnMain(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
