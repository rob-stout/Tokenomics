import Foundation
import os

/// App-wide owner of Claude Code's access token.
///
/// Why a shared actor and not per-provider state: onboarding's `ClaudeConnector`
/// creates its own `ClaudeProvider`, so a per-provider cache would be bypassed and
/// re-read the keychain. One cache means one read, reused until the API says 401.
///
/// We never refresh the token ourselves — refresh tokens are single-use, so doing
/// it would log the user out of Claude Code. We only ever re-read what Claude Code wrote.
///
/// State model: `cachedToken` (working token) · `rejectedTokens` (API said 401; never
/// valid again) · `tokenVersions` (keychain item modification date when each token was
/// obtained) · `staleVersion` (item version known to hold only a dead token). The item's
/// modification date is what separates "Claude Code must run" (version unchanged) from
/// "a newer item exists, offer Allow Access" (version changed) when a silent read can't
/// see the item.
actor ClaudeCredentialStore {
    static let shared = ClaudeCredentialStore()

    /// Injected so tests never touch the real keychain.
    struct Reader: Sendable {
        /// `excluding`: tokens the API rejected. A stale credentials-file copy of
        /// one must not shadow a fresher keychain item.
        var silent: @Sendable (_ excluding: Set<String>) async -> ClaudeCredentialRead
        var interactive: @Sendable (_ excluding: Set<String>) async -> ClaudeCredentialRead
        var modificationDate: @Sendable () async -> Date? = { nil }
        /// A file-sourced token says nothing about the keychain item's version, so it
        /// must never be stamped with that item's modification date.
        var isFileToken: @Sendable (_ token: String) -> Bool = { _ in false }

        static let live = Reader(
            silent: { await KeychainService.readSilently(excluding: $0) },
            interactive: { await KeychainService.readInteractively(excluding: $0) },
            modificationDate: { await KeychainService.itemModificationDate() },
            isFileToken: { KeychainService.isTokenFromFile($0) }
        )
    }

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ClaudeCredentialStore")

    private let reader: Reader
    private var cachedToken: String?
    /// An OAuth access token never becomes valid again, so these are excluded from
    /// every read and never cached or handed out.
    private var rejectedTokens: Set<String> = []
    private var tokenVersions: [String: Date] = [:]
    private var staleVersion: Date?
    /// Coalesces concurrent `requestAccess()` callers (double-tap, popover + Settings
    /// + onboarding) onto one read so the user never sees two macOS dialogs.
    private var inFlightAccess: Task<ClaudeCredentialRead, Never>?

    init(reader: Reader = .live) {
        self.reader = reader
    }

    /// Cached token if we have one (even if Claude Code has since rewritten the item —
    /// a working token is never proactively replaced), else a silent read.
    func currentToken() async -> ClaudeCredentialRead {
        if let cachedToken {
            Self.log.debug("currentToken: cache hit")
            return .found(accessToken: cachedToken)
        }
        var read = await fetch(interactive: false)
        if case .needsAuthorization = read { read = await classifyUnreadable(staleVersion: staleVersion) }
        Self.log.info("currentToken: cache miss, silent read → \(read.logLabel, privacy: .public)")
        return read
    }

    /// The API rejected `previous`. Drop the cache and silently re-read; the caller
    /// treats a different token as "Claude Code rotated" and anything else as "expired"
    /// or "needs access".
    func tokenAfterUnauthorized(previous: String) async -> ClaudeCredentialRead {
        rejectedTokens.insert(previous)
        // Only drop the cache if it still holds the rejected token; a concurrent
        // caller may already have stored a newer one.
        if cachedToken == previous { cachedToken = nil }
        if let cachedToken { return .found(accessToken: cachedToken) }
        var read = await fetch(interactive: false)
        if case .needsAuthorization = read { read = await classifyUnreadable(staleVersion: tokenVersions[previous]) }
        Self.log.info("tokenAfterUnauthorized: silent re-read → \(read.logLabel, privacy: .public)")
        return read
    }

    /// User-initiated. Cached token wins; otherwise a silent read first (access may
    /// already be granted), and only `.needsAuthorization` goes interactive — so at
    /// most ONE macOS dialog, shared by all concurrent callers.
    func requestAccess() async -> ClaudeCredentialRead {
        if let cachedToken { return .found(accessToken: cachedToken) }
        if let inFlightAccess { return await inFlightAccess.value }
        let task = Task { await self.performAccessRequest() }
        inFlightAccess = task
        return await task.value
    }

    private func performAccessRequest() async -> ClaudeCredentialRead {
        var read = await fetch(interactive: false)
        Self.log.info("requestAccess: silent read → \(read.logLabel, privacy: .public)")
        if case .needsAuthorization = read {
            read = await fetch(interactive: true)
            Self.log.info("requestAccess: interactive read → \(read.logLabel, privacy: .public)")
        }
        // Cleared here (not by callers) so a late-resuming waiter can't wipe a newer request.
        inFlightAccess = nil
        return read
    }

    /// One raw read, screened into the store's verdict: rejected tokens become
    /// `.staleToken`, anything usable is cached with the item version it came from.
    private func fetch(interactive: Bool) async -> ClaudeCredentialRead {
        // Version BEFORE the data read: if Claude Code rewrites the item in between,
        // the token is stamped with the older version, so a later 401 looks like
        // "item changed" (offer Allow Access) rather than falsely "still dead"
        // (.authExpired). mdat has 1-second resolution, so this errs toward asking.
        let version = await reader.modificationDate()
        let read = await (interactive ? reader.interactive : reader.silent)(rejectedTokens)
        // Actor reentrancy: a concurrent read/grant may have cached a token while we
        // were suspended. A cached token is never replaced by a late arrival, and a
        // late result must not set stale state while something valid is cached.
        if let cachedToken { return .found(accessToken: cachedToken) }
        guard case .found(let token) = read else { return read }
        if rejectedTokens.contains(token) {
            staleVersion = version
            return .staleToken
        }
        cachedToken = token
        // nil = never stale: a leftover file token that 401s must not mark the keychain
        // version dead.
        tokenVersions[token] = reader.isFileToken(token) ? nil : version
        staleVersion = nil
        return read
    }

    /// A silent read couldn't see the item. If it is still the version known to hold
    /// only a dead token, Claude Code must run (`.staleToken`); if it changed (or we
    /// can't tell), a newer item exists and Allow Access is the right offer.
    private func classifyUnreadable(staleVersion known: Date?) async -> ClaudeCredentialRead {
        guard let known else { return .needsAuthorization }
        let current = await reader.modificationDate()
        if let cachedToken { return .found(accessToken: cachedToken) }
        guard current == known else {
            staleVersion = nil
            return .needsAuthorization
        }
        staleVersion = known
        return .staleToken
    }
}
