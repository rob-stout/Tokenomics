import Foundation
import Security
import os

/// Outcome of looking for Claude Code's OAuth access token.
enum ClaudeCredentialRead: Sendable, Equatable {
    case found(accessToken: String)
    /// No credentials file and no keychain item — Claude Code isn't signed in here.
    case notFound
    /// A keychain item exists but macOS hasn't authorized Tokenomics to read it.
    /// Reading it would show a password dialog, so background callers stop here.
    case needsAuthorization
    /// The only token available is one the API already rejected (an OAuth access token
    /// never becomes valid again). Claude Code must run to refresh it.
    case staleToken
}

extension ClaudeCredentialRead {
    /// Case name only — safe to log (never the token).
    var logLabel: String {
        switch self {
        case .found: return "found"
        case .notFound: return "notFound"
        case .needsAuthorization: return "needsAuthorization"
        case .staleToken: return "staleToken"
        }
    }
}

/// Reads the OAuth credentials stored by Claude Code: the credentials file
/// (~/.claude/.credentials.json) first, then the legacy-keychain item
/// "Claude Code-credentials".
///
/// Why the keychain read is careful: when Claude Code re-logs in it rewrites that
/// item, and its access-control list no longer matches us (also true after a
/// rebuild with a different code signature). Every read then pops a macOS password
/// dialog. So background reads must be *silent*, and the one interactive read only
/// happens when the user explicitly asks for it.
///
/// Both reads try Apple's `security` tool first, which avoids the dialog entirely
/// (see `readViaSecurityTool`); the direct read is the fallback.
enum KeychainService {
    private static let serviceName = "Claude Code-credentials"
    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "KeychainService")

    private static let credentialsFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }()

    /// `SecKeychainSetUserInteractionAllowed` is process-global, so every Claude
    /// keychain read (silent and interactive) runs on this one serial queue. That
    /// guarantees the flag is never flipped while another read is in flight, and
    /// keeps a blocking password dialog off the cooperative thread pool.
    private static let keychainQueue = DispatchQueue(
        label: "com.robstout.tokenomics.claude-keychain",
        qos: .userInitiated
    )

    // MARK: - Public API

    /// Never shows UI. Credentials file, then the keychain with interaction disabled.
    ///
    /// `excluding`: every token the API has rejected. If the credentials file still holds
    /// one of them it would shadow a fresher keychain item, so skip it.
    static func readSilently(excluding rejectedTokens: Set<String> = []) async -> ClaudeCredentialRead {
        if let token = readTokenFromFile(), !rejectedTokens.contains(token) {
            log.debug("silent read satisfied by credentials file")
            return .found(accessToken: token)
        }
        return await onKeychainQueue { readViaSecurityTool() ?? readKeychainItem(interactionAllowed: false) }
    }

    /// May show ONE macOS authorization dialog. Call only in response to a user action.
    ///
    /// `excluding`: same as `readSilently` — a rejected file token must not stop us from
    /// reaching the keychain, otherwise "Allow Access" would never show its dialog.
    static func readInteractively(excluding rejectedTokens: Set<String> = []) async -> ClaudeCredentialRead {
        if let token = readTokenFromFile(), !rejectedTokens.contains(token) { return .found(accessToken: token) }
        return await onKeychainQueue { readViaSecurityTool() ?? readKeychainItem(interactionAllowed: true) }
    }

    /// True if `token` is what the credentials file currently holds. The store uses it
    /// to avoid pinning a file-sourced token to the keychain item's version.
    static func isTokenFromFile(_ token: String) -> Bool {
        readTokenFromFile() == token
    }

    /// When Claude Code last wrote the keychain item, or nil if unknown/absent. The
    /// store uses it as the item's "version" to tell "same dead token" from "Claude
    /// Code re-logged in". Metadata-only queries never prompt (verified), so unlike the
    /// data read this doesn't need the interaction-disabled window; it still shares the
    /// serial queue so it can't interleave with a read that flips that global flag.
    static func itemModificationDate() async -> Date? {
        await withCheckedContinuation { continuation in
            keychainQueue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: serviceName,
                    kSecReturnAttributes as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                let attributes = result as? [String: Any]
                continuation.resume(returning: status == errSecSuccess
                    ? attributes?[kSecAttrModificationDate as String] as? Date : nil)
            }
        }
    }

    // MARK: - Queue bridge

    private static func onKeychainQueue(
        _ work: @escaping @Sendable () -> ClaudeCredentialRead
    ) async -> ClaudeCredentialRead {
        await withCheckedContinuation { continuation in
            keychainQueue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: - Credentials File

    private static func readTokenFromFile() -> String? {
        guard let data = try? Data(contentsOf: credentialsFileURL) else { return nil }
        // Claude Code 2.1.x stopped writing `claudeAiOauth` to this file (it lives
        // in the keychain only — the file holds `mcpOAuth` instead), so a missing
        // key is normal; we just fall through to the keychain.
        return parseAccessToken(from: data)
    }

    // MARK: - Apple's `security` tool

    /// Exit code `security find-generic-password` uses for "no such item".
    private static let securityToolItemNotFound: Int32 = 44

    /// Reads the item through /usr/bin/security, the tool Claude Code itself uses to
    /// write and read it. That makes the tool part of the item's access list and its
    /// "apple-tool:" partition, so this read never shows a dialog. A direct read can't
    /// say the same: each time Claude Code refreshes its login it rewrites the item,
    /// which resets the partition list and wipes the user's "Always Allow".
    ///
    /// Returns nil when the tool can't answer, so the caller falls back to the direct
    /// read. Must run on `keychainQueue`.
    private static func readViaSecurityTool() -> ClaudeCredentialRead? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", serviceName, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("security tool failed to launch: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // If the item's access list ever lacked the tool, it would sit waiting on a
        // dialog. Background reads must never do that, so give up after a few seconds.
        let pid = process.processIdentifier
        let timeout = DispatchWorkItem { kill(pid, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()

        let exitCode = process.terminationReason == .exit ? process.terminationStatus : -1
        let read = mapSecurityTool(exitCode: exitCode, output: data)
        log.info("security tool read: exit \(exitCode) → \(read?.logLabel ?? "fallback", privacy: .public)")
        return read
    }

    /// Pure exit-code → result mapping, unit-testable without running the tool.
    /// nil means "no answer, try the direct read".
    static func mapSecurityTool(exitCode: Int32, output: Data) -> ClaudeCredentialRead? {
        switch exitCode {
        case 0:
            guard let token = parseAccessToken(from: output) else { return nil }
            return .found(accessToken: token)
        case securityToolItemNotFound:
            return .notFound
        default:
            return nil
        }
    }

    // MARK: - Keychain

    /// Must run on `keychainQueue`.
    private static func readKeychainItem(interactionAllowed: Bool) -> ClaudeCredentialRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        var status: OSStatus
        if interactionAllowed {
            status = SecItemCopyMatching(query as CFDictionary, &result)
        } else {
            // The only mechanism that actually suppresses the legacy-keychain ACL
            // dialog (verified on macOS 26): LAContext.interactionNotAllowed and
            // kSecUseAuthenticationUIFail both still show it. The API is deprecated
            // and process-global, hence the serial queue, the minimal window, and
            // the deferred restore.
            var previous = DarwinBoolean(true)
            SecKeychainGetUserInteractionAllowed(&previous)
            SecKeychainSetUserInteractionAllowed(false)
            defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        let read = map(status: status, data: result as? Data)
        log.info("keychain read (\(interactionAllowed ? "interactive" : "silent", privacy: .public)) OSStatus \(status) → \(read.logLabel, privacy: .public)")
        return read
    }

    /// Pure status → result mapping, separated so it's unit-testable without a keychain.
    static func map(status: OSStatus, data: Data?) -> ClaudeCredentialRead {
        switch status {
        case errSecSuccess:
            guard let data, let token = parseAccessToken(from: data) else {
                log.info("keychain item present but contains no usable access token")
                return .notFound
            }
            return .found(accessToken: token)
        case errSecItemNotFound:
            return .notFound
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            return .needsAuthorization
        default:
            // Unknown failure: treat as "needs authorization" — a tap shows at most one
            // dialog, whereas .notFound would send the user through a needless re-login.
            log.error("keychain read failed with unexpected status \(status)")
            return .needsAuthorization
        }
    }

    // MARK: - Parsing

    /// Accepts the JSON blob Claude Code stores, with a legacy string-scan fallback
    /// for older item formats. Only the access token is kept — we never hold
    /// Claude Code's refresh token.
    static func parseAccessToken(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String,
           token.hasPrefix("sk-ant-") {
            return token
        }

        guard let raw = String(data: data, encoding: .utf8),
              let startRange = raw.range(of: "\"accessToken\":\""),
              let endQuote = raw[startRange.upperBound...].firstIndex(of: "\"") else {
            return nil
        }
        let token = String(raw[startRange.upperBound..<endQuote])
        return token.hasPrefix("sk-ant-") ? token : nil
    }
}
