import Foundation
import Security

/// Reads the OAuth token stored by Claude Code in the macOS Keychain
enum KeychainService {
    private static let serviceName = "Claude Code-credentials"

    /// Reads the Claude OAuth access token from Keychain.
    ///
    /// Claude Code stores a large JSON blob containing OAuth tokens for multiple
    /// services (Claude, Figma, Asana, etc.). macOS Keychain can truncate the
    /// returned data for large items, making full JSON parsing fail.
    /// We extract the access token directly from the raw string instead,
    /// since it always appears near the start of the blob.
    static func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Look for the accessToken value inside the claudeAiOauth object.
        // Pattern: "accessToken":"<token>" — grab everything between the quotes.
        guard let startRange = raw.range(of: "\"accessToken\":\"") else {
            return nil
        }

        let tokenStart = startRange.upperBound
        guard let endQuote = raw[tokenStart...].firstIndex(of: "\"") else {
            return nil
        }

        let token = String(raw[tokenStart..<endQuote])

        // Sanity check — Claude OAuth tokens start with this prefix
        guard token.hasPrefix("sk-ant-") else {
            return nil
        }

        return token
    }
}
