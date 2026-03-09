import Foundation
import os

/// Claude Code usage provider — wraps the existing UsageService + KeychainService
///
/// Token strategy: always re-read from the Keychain on each fetch. Claude Code
/// refreshes its own token during normal use, so we piggyback on that. We never
/// call the refresh endpoint ourselves because doing so invalidates Claude Code's
/// refresh token (they're single-use) and logs the user out.
actor ClaudeProvider: UsageProvider {
    let id = ProviderId.claude
    let pollInterval: TimeInterval = 600 // 10 min — remote API with tight rate limits

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ClaudeProvider")

    private let usageService = UsageService()

    /// Track the last token we used so we can detect when Claude Code has refreshed
    private var lastUsedToken: String?

    func checkConnection() async -> ProviderConnectionState {
        if KeychainService.readAccessToken() != nil {
            return .connected(plan: "—")
        }
        if isClaudeCodeInstalled() { return .installedNoAuth }
        return .notInstalled
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let token = try readToken()

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
            // Claude Code may have refreshed — re-read from Keychain and retry once
            Self.log.info("Token expired — re-reading from Keychain")
            let freshToken = try readToken()
            if freshToken != token {
                lastUsedToken = freshToken
                await usageService.resetRateLimit()
                let data = try await usageService.fetchUsage(token: freshToken)
                return mapToSnapshot(data)
            }
            throw error
        }
    }

    // MARK: - Private

    private func readToken() throws -> String {
        guard let token = KeychainService.readAccessToken() else {
            throw AppError.notAuthenticated
        }
        return token
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
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "5-Hour Window",
                utilization: data.fiveHour.utilization,
                resetsAt: data.fiveHour.resetsAt,
                windowDuration: 5 * 3600
            ),
            longWindow: WindowUsage(
                label: "7-Day Window",
                utilization: data.sevenDay.utilization,
                resetsAt: data.sevenDay.resetsAt,
                windowDuration: 7 * 24 * 3600
            ),
            planLabel: data.inferredPlan.rawValue,
            extraUsage: data.extraUsage,
            creditsBalance: nil
        )
    }
}
