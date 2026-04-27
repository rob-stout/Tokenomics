import Foundation
import AppKit
import os

/// Quick-mode connector for GitHub Copilot.
///
/// Detection: delegates to `CopilotProvider.checkConnection()`. The existing
/// flow auths via a fine-grained Personal Access Token stored in Keychain
/// (`CopilotKeychainService.savePAT`).
///
/// Primary action: surfaces the existing PAT entry sheet by flipping
/// `UsageViewModel.copilotPATEntryRequested`. The eventual OAuth flow
/// (Cloudflare Worker on trytokenomics.com) replaces this — kept as fallback.
actor CopilotConnector: ProviderConnector {
    nonisolated let id: ProviderId = .copilot
    nonisolated let mode: ConnectorMode = .quick

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CopilotConnector")

    private let provider: CopilotProvider
    private let onRequestAuth: @Sendable @MainActor () -> Void

    init(provider: CopilotProvider = CopilotProvider(),
         onRequestAuth: @escaping @Sendable @MainActor () -> Void) {
        self.provider = provider
        self.onRequestAuth = onRequestAuth
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
        await MainActor.run { [onRequestAuth] in
            onRequestAuth()
        }
    }

    func cancel() async {}
}
