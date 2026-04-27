import Foundation
import AppKit
import os

/// Quick-mode connector for Anthropic Claude.
///
/// Detection: delegates to `ClaudeProvider.checkConnection()`. If the user
/// already has Claude Code installed and signed in (`~/.claude/.credentials.json`
/// → Keychain bearer token → 200 from the usage endpoint), Tokenomics shows
/// `.connected`. Otherwise the primary action opens the setup guide.
///
/// **Why no in-app OAuth**: Anthropic's Feb 2026 OpenClaw policy prohibits
/// third-party apps from using Pro/Max OAuth tokens. The plan calls out an
/// API-key sub-flow as the officially supported path; that lives in Settings →
/// Connections → Anthropic for now (existing API key entry sheet).
actor ClaudeConnector: ProviderConnector {
    nonisolated let id: ProviderId = .claude
    nonisolated let mode: ConnectorMode = .quick

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ClaudeConnector")
    private static let setupURL = URL(string: "https://trytokenomics.com/setup.html#anthropic")!

    private let provider: ClaudeProvider

    init(provider: ClaudeProvider = ClaudeProvider()) {
        self.provider = provider
    }

    func currentStep() async -> ConnectorStep {
        let state = await provider.checkConnection()
        switch state {
        case .connected(let plan): return .connected(plan: plan)
        case .notInstalled, .installedNoAuth, .authExpired: return .needsAction
        case .unavailable(let reason): return .failed(.unknown(reason))
        }
    }

    func performPrimaryAction() async {
        // Hand off to the setup guide. The Anthropic section explains the two
        // supported paths (existing Claude Code install OR API key entry).
        await openOnMain(Self.setupURL)
    }

    func cancel() async {}

    @MainActor
    private func openOnMain(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
