import Foundation
import AppKit
import os

/// Guided-mode connector for OpenAI's Codex CLI.
///
/// Detection: delegates to `CodexProvider.checkConnection()`. If the user has
/// already installed the CLI and signed in, Tokenomics shows `.connected`.
///
/// **Primary action**: opens the setup guide. The bundled-Node Guided flow
/// (Phase 2 of the plan — Tokenomics ships Node, runs `npm install` as a
/// hidden subprocess, surfaces the device-code URL natively) is not yet
/// implemented; this connector falls back to the documented Terminal path.
actor CodexConnector: ProviderConnector {
    nonisolated let id: ProviderId = .codex
    nonisolated let mode: ConnectorMode = .guided

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CodexConnector")
    private static let setupURL = URL(string: "https://trytokenomics.com/setup.html#openai")!

    private let provider: CodexProvider

    init(provider: CodexProvider = CodexProvider()) {
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
        await openOnMain(Self.setupURL)
    }

    func cancel() async {}

    @MainActor
    private func openOnMain(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
