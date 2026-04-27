import Foundation
import AppKit
import os

/// Guided-mode connector for Google's Gemini CLI.
///
/// Same shape as CodexConnector — see that file for architecture notes.
/// Detection delegates to `GeminiProvider.checkConnection()`; primary action
/// hands off to the setup guide until Phase 2's bundled-Node flow ships.
actor GeminiConnector: ProviderConnector {
    nonisolated let id: ProviderId = .gemini
    nonisolated let mode: ConnectorMode = .guided

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "GeminiConnector")
    private static let setupURL = URL(string: "https://trytokenomics.com/setup.html#google")!

    private let provider: GeminiProvider

    init(provider: GeminiProvider = GeminiProvider()) {
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
