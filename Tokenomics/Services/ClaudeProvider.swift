import Foundation
import os

/// Claude Code usage provider — wraps UsageService; tokens come from `ClaudeCredentialStore`.
///
/// Token strategy: the shared store caches the token Claude Code wrote and we reuse
/// it until the usage API returns 401. Only then do we silently re-read, piggybacking
/// on Claude Code's own refresh. We never call the refresh endpoint ourselves because
/// doing so invalidates Claude Code's refresh token (they're single-use) and logs the
/// user out.
actor ClaudeProvider: UsageProvider {
    let id = ProviderId.claude
    // 3 min — the community-verified safe polling floor for /api/oauth/usage
    // when the claude-code User-Agent is sent (without that header the endpoint
    // uses a hostile rate-limit bucket; see Claude-Code-Usage-Monitor#202).
    // The limiter also punishes simultaneous requests — UsageService
    // single-flights concurrent callers.
    let pollInterval: TimeInterval = 180

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ClaudeProvider")

    private let usageService = UsageService()
    private let credentials: ClaudeCredentialStore

    init(credentials: ClaudeCredentialStore = .shared) {
        self.credentials = credentials
    }

    /// Track the last token we used so we can detect when Claude Code has refreshed
    private var lastUsedToken: String?

    /// Cache the last validation result. checkConnection() now hits the API
    /// to confirm the token actually works (not just that it exists in the
    /// Keychain) — but the connector polls every 1.5s during onboarding and
    /// we mustn't hammer Anthropic's usage endpoint. 5s is short enough to
    /// stay responsive when the user finishes sign-in in Terminal, long
    /// enough to amortise polling to ~one network call per cycle.
    private var cachedConnectionState: (state: ProviderConnectionState, asOf: Date)?
    private static let connectionCacheTTL: TimeInterval = 5.0

    func checkConnection() async -> ProviderConnectionState {
        // One store lookup per call; the token is passed down so validation
        // below doesn't trigger a second read.
        let token: String
        switch await credentials.currentToken() {
        case .found(let found):
            token = found
        case .notFound:
            // No token anywhere — drop any stale cache and report the
            // installation state. A fresh sign-in attempt should re-validate
            // from scratch, not see a remembered "expired" verdict.
            cachedConnectionState = nil
            return notSignedInState()
        case .needsAuthorization:
            Self.log.info("checkConnection → needsKeychainAccess (silent read not authorized)")
            cachedConnectionState = nil
            return .needsKeychainAccess
        case .staleToken:
            // Only a rejected token is available; Claude Code must refresh it.
            Self.log.info("checkConnection → authExpired (only a rejected token exists)")
            cachedConnectionState = nil
            return .authExpired
        }

        // Token exists — but is it still valid? Reuse the cached validation
        // result if it's recent enough (see connectionCacheTTL rationale).
        if let cached = cachedConnectionState,
           Date().timeIntervalSince(cached.asOf) < Self.connectionCacheTTL {
            return cached.state
        }

        // Validate by attempting a real fetch. The previous implementation
        // returned .connected purely on token presence, which made the
        // onboarding "connected" screen flash green even when fetchUsage
        // would 401 a moment later (Bug I). We now only declare .connected
        // when the fetch actually succeeds, and surface .authExpired on 401
        // so the connector routes back to the Terminal re-auth path.
        let state: ProviderConnectionState
        do {
            let snapshot = try await fetchUsage(using: token)
            state = .connected(plan: snapshot.planLabel)
        } catch let error as AppError where error.isTokenExpired {
            Self.log.info("checkConnection → authExpired (token rejected, Claude Code must re-login)")
            state = .authExpired
        } catch let error as AppError where error.needsKeychainAccess {
            Self.log.info("checkConnection → needsKeychainAccess (after 401 re-read)")
            cachedConnectionState = nil
            return .needsKeychainAccess
        } catch AppError.notAuthenticated {
            // Token vanished during the 401 re-read.
            cachedConnectionState = nil
            return notSignedInState()
        } catch {
            // Network blip or transient failure — don't lock the user out of
            // onboarding. Fall back to cached usage's plan label if any,
            // otherwise leave it blank (Bug J: never default to "Pro" — that
            // misrepresents Max and Free users alike).
            let plan = SettingsService.cachedUsage(for: .claude)?.snapshot.planLabel ?? ""
            state = .connected(plan: plan)
        }

        cachedConnectionState = (state, Date())
        return state
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        switch await credentials.currentToken() {
        case .found(let token): return try await fetchUsage(using: token)
        case .notFound: throw AppError.notAuthenticated
        case .needsAuthorization: throw AppError.keychainAccessNeeded
        case .staleToken: throw AppError.tokenExpired
        }
    }

    // MARK: - Private

    private func fetchUsage(using token: String) async throws -> ProviderUsageSnapshot {
        // If Claude Code refreshed since our last fetch, we have a fresh token
        // which also means a fresh rate-limit window — clear any backoff state
        if let previous = lastUsedToken, token != previous {
            Self.log.info("Detected token rotation by Claude Code — clearing rate limit backoff")
            await usageService.resetRateLimit()
        }
        lastUsedToken = token

        do {
            let data = try await usageService.fetchUsage(token: token)
            return mapToSnapshot(data)
        } catch let error as AppError where error.isTokenExpired {
            // Claude Code may have refreshed — silently re-read and retry once
            Self.log.info("Token rejected — re-reading silently")
            switch await credentials.tokenAfterUnauthorized(previous: token) {
            case .found(let freshToken) where freshToken != token:
                lastUsedToken = freshToken
                await usageService.resetRateLimit()
                let data = try await usageService.fetchUsage(token: freshToken)
                return mapToSnapshot(data)
            case .found, .staleToken:
                // Same (or an already-rejected) token: Claude Code hasn't re-authenticated,
                // so the user must. Also covers a one-time "Allow" token that has since expired.
                Self.log.info("fetchUsage: 401 and no newer token → authExpired")
                throw error
            case .needsAuthorization:
                Self.log.info("fetchUsage: 401 re-read needs keychain authorization")
                throw AppError.keychainAccessNeeded
            case .notFound:
                throw AppError.notAuthenticated
            }
        }
    }

    private func notSignedInState() -> ProviderConnectionState {
        isClaudeCodeInstalled() ? .installedNoAuth : .notInstalled
    }

    private func isClaudeCodeInstalled() -> Bool {
        let paths = [
            "\(NSHomeDirectory())/.claude/.credentials.json",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.claude/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func mapToSnapshot(_ data: UsageData) -> ProviderUsageSnapshot {
        // Anthropic returns `resets_at: null` when a window has no active
        // reset cycle yet (e.g. zero usage). `.distantFuture` is only a pace
        // sentinel here — without an override, timeUntilReset would format it
        // as a real calendar date ("Resets Sunday"), so we say so plainly instead.
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "5-Hour Window",
                utilization: data.fiveHour.utilization,
                resetsAt: data.fiveHour.resetsAt ?? .distantFuture,
                windowDuration: 5 * 3600,
                sublabelOverride: data.fiveHour.resetsAt == nil ? "No active session" : nil
            ),
            longWindow: WindowUsage(
                label: "7-Day Window",
                utilization: data.sevenDay.utilization,
                resetsAt: data.sevenDay.resetsAt ?? .distantFuture,
                windowDuration: 7 * 24 * 3600,
                sublabelOverride: data.sevenDay.resetsAt == nil ? "No usage yet" : nil
            ),
            planLabel: data.inferredPlan.rawValue,
            extraUsage: data.extraUsage,
            creditsBalance: nil
        )
    }
}
