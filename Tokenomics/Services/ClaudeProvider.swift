import Foundation

/// Claude Code usage provider — wraps the existing UsageService + KeychainService
actor ClaudeProvider: UsageProvider {
    let id = ProviderId.claude
    let pollInterval: TimeInterval = 600 // 10 min — remote API with tight rate limits

    private let usageService = UsageService()
    private var cachedToken: String?

    func checkConnection() async -> ProviderConnectionState {
        // Claude Code stores credentials in ~/.claude/.credentials.json (and Keychain).
        // Only check token presence — don't call the API here.
        // Usage fetch will validate the token and update state on the first poll.
        if readToken() != nil {
            return .connected(plan: "—")
        }

        // Check if Claude Code is installed by looking for the Keychain service
        // entry (even if empty). No entry at all means not installed.
        if isClaudeCodeInstalled() {
            return .installedNoAuth
        }

        return .notInstalled
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        if cachedToken == nil {
            cachedToken = readToken()
        }

        guard let token = cachedToken else {
            throw AppError.notAuthenticated
        }

        do {
            let data = try await usageService.fetchUsage(token: token)
            return mapToSnapshot(data)
        } catch let error as AppError where error.isTokenExpired {
            // Token rotated — try once more with a fresh Keychain read
            cachedToken = nil
            cachedToken = readToken()
            guard let freshToken = cachedToken else {
                throw AppError.tokenExpired
            }
            let data = try await usageService.fetchUsage(token: freshToken)
            return mapToSnapshot(data)
        }
    }

    /// Clear cached token (called by ViewModel on auth errors)
    func clearCachedToken() {
        cachedToken = nil
    }

    // MARK: - Private

    private func readToken() -> String? {
        KeychainService.readAccessToken()
    }

    private func isClaudeCodeInstalled() -> Bool {
        // Check for the credentials file or CLI binary in common paths.
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
