import Foundation
import os

/// Quick-mode connector for API-key providers — Stability AI, Runway, ElevenLabs.
///
/// All three share the same shape: detection checks Keychain via `APIKeyService`
/// (already wrapped inside each provider's `checkConnection()`). Primary action
/// surfaces the existing API key entry sheet by setting
/// `UsageViewModel.apiKeyEntryProvider` on MainActor.
actor APIKeyConnector: ProviderConnector {
    nonisolated let id: ProviderId
    nonisolated let mode: ConnectorMode = .quick

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "APIKeyConnector")

    private let provider: any UsageProvider
    private let onRequestKey: @Sendable @MainActor () -> Void

    init(providerId: ProviderId,
         provider: any UsageProvider,
         onRequestKey: @escaping @Sendable @MainActor () -> Void) {
        self.id = providerId
        self.provider = provider
        self.onRequestKey = onRequestKey
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
        await MainActor.run { [onRequestKey] in
            onRequestKey()
        }
    }

    func cancel() async {}
}
