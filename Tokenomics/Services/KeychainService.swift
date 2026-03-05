import Foundation
import Security

/// Reads the OAuth token stored by Claude Code, preferring the credentials
/// file (~/.claude/.credentials.json) over the macOS Keychain to avoid
/// repeated keychain access prompts during development.
enum KeychainService {
    private static let serviceName = "Claude Code-credentials"

    private static let credentialsFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }()

    static func readAccessToken() -> String? {
        // Prefer the credentials file — no keychain prompt required
        if let token = readFromCredentialsFile() {
            return token
        }
        // Fall back to Keychain for older Claude Code versions
        return readFromKeychain()
    }

    // MARK: - Credentials File

    /// Reads the access token from ~/.claude/.credentials.json
    private static func readFromCredentialsFile() -> String? {
        guard let data = try? Data(contentsOf: credentialsFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              token.hasPrefix("sk-ant-") else {
            return nil
        }
        return token
    }

    // MARK: - Keychain (fallback)

    private static func readFromKeychain() -> String? {
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

        guard let startRange = raw.range(of: "\"accessToken\":\"") else {
            return nil
        }

        let tokenStart = startRange.upperBound
        guard let endQuote = raw[tokenStart...].firstIndex(of: "\"") else {
            return nil
        }

        let token = String(raw[tokenStart..<endQuote])

        guard token.hasPrefix("sk-ant-") else {
            return nil
        }

        return token
    }
}
