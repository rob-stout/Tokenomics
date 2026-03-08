import Foundation
import os

/// Claude Code usage provider — wraps the existing UsageService + KeychainService
actor ClaudeProvider: UsageProvider {
    let id = ProviderId.claude
    let pollInterval: TimeInterval = 600 // 10 min — remote API with tight rate limits

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ClaudeProvider")

    private let usageService = UsageService()
    private let tokenRefreshService = TokenRefreshService()
    private var cachedCredentials: KeychainService.OAuthCredentials?

    func checkConnection() async -> ProviderConnectionState {
        // Only check token presence — don't call the API here.
        if KeychainService.readAccessToken() != nil {
            return .connected(plan: "—")
        }
        if isClaudeCodeInstalled() { return .installedNoAuth }
        return .notInstalled
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let token = try await getValidToken()
        do {
            let data = try await usageService.fetchUsage(token: token)
            return mapToSnapshot(data)
        } catch let error as AppError where error.isTokenExpired {
            // Token might have been rotated — re-read and retry once
            cachedCredentials = nil
            let freshToken = try await getValidToken()
            let data = try await usageService.fetchUsage(token: freshToken)
            return mapToSnapshot(data)
        }
    }

    /// Clear cached credentials (called by ViewModel on auth errors)
    func clearCachedToken() {
        cachedCredentials = nil
    }

    // MARK: - Token Management

    /// Returns a valid access token, refreshing if expired
    private func getValidToken() async throws -> String {
        if cachedCredentials == nil {
            cachedCredentials = KeychainService.readCredentials()
        }

        guard let creds = cachedCredentials else {
            throw AppError.notAuthenticated
        }

        // If token is expired or about to expire, try refreshing
        if TokenRefreshService.needsRefresh(expiresAt: creds.expiresAt) {
            if let refreshToken = creds.refreshToken {
                Self.log.info("Token expired or expiring soon — refreshing")
                do {
                    let result = try await tokenRefreshService.refresh(using: refreshToken)
                    // Update cached credentials with new token
                    cachedCredentials = KeychainService.OAuthCredentials(
                        accessToken: result.accessToken,
                        refreshToken: result.refreshToken,
                        expiresAt: Date().addingTimeInterval(result.expiresIn)
                    )
                    return result.accessToken
                } catch {
                    Self.log.warning("Token refresh failed: \(error.localizedDescription) — using existing token")
                }
            }
        }

        return creds.accessToken
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
