import Foundation
import os

/// Generic Keychain service for storing API keys per provider.
///
/// Used by API-key-based providers (ElevenLabs, Runway, Stable Diffusion).
/// Keys are stored under a per-provider service name so they're independently
/// readable and deletable without affecting other providers.
enum APIKeyService {
    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "APIKeyService")

    private static func serviceName(for provider: ProviderId) -> String {
        "com.robstout.tokenomics.apikey.\(provider.rawValue)"
    }

    /// Read the stored API key for a provider. Returns nil if none is saved.
    static func read(for provider: ProviderId) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            if status != errSecSuccess && status != errSecItemNotFound {
                log.error("Keychain read failed for \(provider.rawValue): OSStatus \(status)")
            }
            return nil
        }
        return key
    }

    /// Save an API key for a provider, replacing any existing value.
    static func save(_ key: String, for provider: ProviderId) {
        delete(for: provider)
        guard let data = key.data(using: .utf8) else { return }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: provider),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Failed to save API key for \(provider.rawValue): \(status)")
        }
    }

    /// Delete the stored API key for a provider.
    static func delete(for provider: ProviderId) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: provider)
        ]
        SecItemDelete(query as CFDictionary)
    }
}
