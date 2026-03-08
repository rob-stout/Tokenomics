import Foundation
import Security
import os

/// Reads the OAuth credentials stored by Claude Code, preferring the credentials
/// file (~/.claude/.credentials.json) over the macOS Keychain to avoid
/// repeated keychain access prompts during development.
enum KeychainService {
    private static let serviceName = "Claude Code-credentials"
    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "KeychainService")

    private static let credentialsFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }()

    /// Full OAuth credentials needed for token refresh
    struct OAuthCredentials {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    static func readAccessToken() -> String? {
        readCredentials()?.accessToken
    }

    /// Read full OAuth credentials (token + refresh token + expiry)
    static func readCredentials() -> OAuthCredentials? {
        if let creds = readCredentialsFromFile() { return creds }
        return readCredentialsFromKeychain()
    }

    // MARK: - Credentials File

    private static func readCredentialsFromFile() -> OAuthCredentials? {
        guard let data = try? Data(contentsOf: credentialsFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              token.hasPrefix("sk-ant-") else {
            return nil
        }
        let refreshToken = oauth["refreshToken"] as? String
        let expiresAt: Date? = {
            guard let ms = oauth["expiresAt"] as? Double else { return nil }
            return Date(timeIntervalSince1970: ms / 1000)
        }()
        return OAuthCredentials(accessToken: token, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    // MARK: - Keychain (fallback)

    private static func readCredentialsFromKeychain() -> OAuthCredentials? {
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

        // Parse as JSON for full credential access
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String,
           token.hasPrefix("sk-ant-") {
            let refreshToken = oauth["refreshToken"] as? String
            let expiresAt: Date? = {
                guard let ms = oauth["expiresAt"] as? Double else { return nil }
                return Date(timeIntervalSince1970: ms / 1000)
            }()
            return OAuthCredentials(accessToken: token, refreshToken: refreshToken, expiresAt: expiresAt)
        }

        // Legacy string-parsing fallback
        guard let startRange = raw.range(of: "\"accessToken\":\"") else {
            return nil
        }
        let tokenStart = startRange.upperBound
        guard let endQuote = raw[tokenStart...].firstIndex(of: "\"") else {
            return nil
        }
        let token = String(raw[tokenStart..<endQuote])
        guard token.hasPrefix("sk-ant-") else { return nil }
        return OAuthCredentials(accessToken: token, refreshToken: nil, expiresAt: nil)
    }
}
