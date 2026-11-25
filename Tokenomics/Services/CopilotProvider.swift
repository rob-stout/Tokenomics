import Foundation
import os

/// GitHub Copilot usage provider — zero-friction auth via `gh` CLI token.
///
/// Auth: reads the token from `gh auth token` (stored in the system keyring by
/// the GitHub CLI). No PAT or manual setup required.
///
/// API: `GET https://api.github.com/copilot_internal/user` — returns remaining
/// quotas, monthly limits, plan type, and reset date. Works for both free and
/// paid users with the standard gh CLI token.
actor CopilotProvider: UsageProvider {
    let id = ProviderId.copilot
    let pollInterval: TimeInterval = 300 // 5 min — lightweight internal endpoint

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CopilotProvider")

    func checkConnection() async -> ProviderConnectionState {
        if let forced = DetectionScenario.current.forcedConnection { return forced }
        guard let token = readToken() else {
            if isGitHubCLIInstalled() { return .installedNoAuth }
            return .notInstalled
        }

        do {
            let userInfo = try await fetchCopilotUser(token: token)
            let plan = userInfo.planLabel
            return .connected(plan: plan)
        } catch {
            Self.log.warning("Copilot connection check failed: \(error.localizedDescription)")
            // Token exists but Copilot isn't enabled for this account
            return .installedNoAuth
        }
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        guard let token = readToken() else {
            throw AppError.notAuthenticated
        }

        let userInfo = try await fetchCopilotUser(token: token)
        return Self.mapToSnapshot(userInfo)
    }

    // MARK: - Token Reading

    /// Read token via `gh auth token` (gh stores tokens in the system keyring)
    private func readToken() -> String? {
        // Check for a manually-saved PAT first (legacy fallback)
        if let pat = CopilotKeychainService.readPAT() {
            return pat
        }

        let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        guard let ghPath = ghPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["auth", "token"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (token?.isEmpty == false) ? token : nil
        } catch {
            Self.log.error("gh auth token subprocess failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func isGitHubCLIInstalled() -> Bool {
        let paths = [
            "/usr/local/bin/gh",
            "/opt/homebrew/bin/gh",
            "\(NSHomeDirectory())/.config/gh/hosts.yml"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Copilot Internal API

    private func fetchCopilotUser(token: String) async throws -> CopilotUserInfo {
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(CopilotUserInfo.self, from: data)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401: throw AppError.tokenExpired
        case 403: throw AppError.notAuthenticated
        case 404: throw AppError.httpError(statusCode: 404)
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw AppError.rateLimited(retryAfter: retryAfter)
        default:
            throw AppError.httpError(statusCode: http.statusCode)
        }
    }

    // MARK: - Mapping

    /// Static so tests can exercise the mapping with fixture JSON.
    nonisolated static func mapToSnapshot(_ info: CopilotUserInfo) -> ProviderUsageSnapshot {
        // Free accounts report counted quotas here; keep that path first so their
        // behaviour is unchanged. Paid plans omit it and use `quota_snapshots`.
        let freeFromSnapshots = info.isFreeViaSnapshots
        if info.monthlyQuotas?.chat == nil, !freeFromSnapshots,
           let premium = info.quotaSnapshots?.premiumInteractions {
            return mapPaidSnapshot(info, premium: premium)
        }
        // Free accounts: prefer the legacy counted quotas, else the 2026 snapshots
        // (premium has no quota there, chat/completions carry the limits).
        let chatQuota = info.limitedUserQuotas?.chat ?? info.quotaSnapshots?.chat?.remaining ?? 0
        let chatLimit = info.monthlyQuotas?.chat ?? info.quotaSnapshots?.chat?.entitlement ?? 0
        let chatUsed = chatLimit - chatQuota

        let completionsQuota = info.limitedUserQuotas?.completions ?? info.quotaSnapshots?.completions?.remaining ?? 0
        let completionsLimit = info.monthlyQuotas?.completions ?? info.quotaSnapshots?.completions?.entitlement ?? 0
        let completionsUsed = completionsLimit - completionsQuota

        let chatUtilization = chatLimit > 0
            ? Double(chatUsed) / Double(chatLimit) * 100 : 0
        let completionsUtilization = completionsLimit > 0
            ? Double(completionsUsed) / Double(completionsLimit) * 100 : 0

        // Parse reset date
        let resetsAt: Date
        if let resetStr = info.limitedUserResetDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            resetsAt = formatter.date(from: resetStr) ?? Date.distantFuture
        } else if let paidReset = info.paidResetDate {
            resetsAt = paidReset
        } else {
            resetsAt = Date.distantFuture
        }

        // Estimate cycle start (reset date minus ~30 days)
        let calendar = Calendar.current
        let cycleStart = calendar.date(byAdding: .month, value: -1, to: resetsAt) ?? Date()
        let cycleDuration = resetsAt.timeIntervalSince(cycleStart)

        // Short window: chat requests (the tighter constraint for most users)
        let shortWindow = WindowUsage(
            label: "Chat",
            utilization: min(chatUtilization, 999),
            resetsAt: resetsAt,
            windowDuration: cycleDuration,
            sublabelOverride: "\(chatUsed) / \(chatLimit) used"
        )

        // Long window: completions (higher limit, secondary metric)
        let longWindow: WindowUsage?
        if completionsLimit > 0 {
            longWindow = WindowUsage(
                label: "Completions",
                utilization: min(completionsUtilization, 999),
                resetsAt: resetsAt,
                windowDuration: cycleDuration,
                sublabelOverride: "\(completionsUsed) / \(completionsLimit) used"
            )
        } else {
            longWindow = nil
        }

        return ProviderUsageSnapshot(
            shortWindow: shortWindow,
            longWindow: longWindow,
            planLabel: info.planLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    /// Paid plans (Pro, Pro+, Business, Enterprise): chat and completions are
    /// unlimited, so the only meter that matters is AI credits (monthly plans) or
    /// premium requests (annual Pro/Pro+).
    private nonisolated static func mapPaidSnapshot(
        _ info: CopilotUserInfo,
        premium: CopilotUserInfo.QuotaSnapshot
    ) -> ProviderUsageSnapshot {
        let resetsAt = info.paidResetDate ?? Date.distantFuture
        let cycleStart = Calendar.current.date(byAdding: .month, value: -1, to: resetsAt) ?? Date()
        let cycleDuration = resetsAt.timeIntervalSince(cycleStart)

        // Monthly paid plans moved to token-based "AI credits" in June 2026; annual
        // Pro/Pro+ keep premium requests. The snapshot flag wins over the top-level one.
        let isTokenBased = premium.tokenBasedBilling ?? info.tokenBasedBilling ?? false
        let entitlement = premium.entitlement ?? 0
        let utilization: Double
        let sublabel: String
        if premium.unlimited == true || entitlement <= 0 {
            utilization = 0
            sublabel = "Unlimited"
        } else {
            // percent_remaining is fractional (e.g. 87.3) and more precise than the
            // integer `remaining`; fall back to remaining when it is absent.
            let usedPercent: Double
            if isTokenBased, let credits = premium.creditsUsed, credits >= 0 {
                usedPercent = credits / Double(entitlement) * 100
            } else if let percentRemaining = premium.percentRemaining {
                usedPercent = 100 - percentRemaining
            } else if let remaining = premium.remaining {
                usedPercent = Double(entitlement - remaining) / Double(entitlement) * 100
            } else {
                usedPercent = 0
            }
            utilization = max(0, usedPercent)
            let used: Int
            if isTokenBased, let credits = premium.creditsUsed, credits >= 0 {
                used = Int(credits.rounded())
            } else {
                used = Int((Double(entitlement) * utilization / 100).rounded())
            }
            sublabel = "\(used) / \(entitlement) used"
        }

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: isTokenBased ? "AI Credits" : "Premium Requests",
                utilization: min(utilization, 999),
                resetsAt: resetsAt,
                windowDuration: cycleDuration,
                sublabelOverride: sublabel
            ),
            longWindow: nil,
            planLabel: info.planLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }
}

// MARK: - Response Model

struct CopilotUserInfo: Decodable {
    let login: String?
    let accessTypeSku: String?
    let copilotPlan: String?
    let chatEnabled: Bool?
    let limitedUserQuotas: Quotas?
    let limitedUserResetDate: String?
    let monthlyQuotas: Quotas?
    let quotaSnapshots: QuotaSnapshots?
    let quotaResetDate: String?
    let quotaResetDateUTC: String?
    let tokenBasedBilling: Bool?

    struct QuotaSnapshots: Decodable {
        let chat: QuotaSnapshot?
        let completions: QuotaSnapshot?
        let premiumInteractions: QuotaSnapshot?

        enum CodingKeys: String, CodingKey {
            case chat, completions
            case premiumInteractions = "premium_interactions"
        }
    }

    struct QuotaSnapshot: Decodable {
        let entitlement: Int?
        let remaining: Int?
        let percentRemaining: Double?
        let unlimited: Bool?
        let hasQuota: Bool?
        // Added with token-based billing (June 2026); absent on older responses.
        let tokenBasedBilling: Bool?
        let creditsUsed: Double?

        enum CodingKeys: String, CodingKey {
            case entitlement, remaining, unlimited
            case hasQuota = "has_quota"
            case tokenBasedBilling = "token_based_billing"
            case creditsUsed = "credits_used"
            case percentRemaining = "percent_remaining"
        }
    }

    /// Free accounts in the 2026 response shape: no premium quota, but counted
    /// chat/completions snapshots.
    var isFreeViaSnapshots: Bool {
        guard let snaps = quotaSnapshots,
              snaps.premiumInteractions?.hasQuota == false,
              snaps.premiumInteractions?.unlimited != true,
              snaps.chat?.unlimited != true,
              (snaps.chat?.entitlement ?? 0) > 0 else { return false }
        return true
    }

    /// Paid plans send "2026-12-01" and/or "2026-12-01T00:00:00.000Z"; only the
    /// date part matters, and it is a UTC date.
    var paidResetDate: Date? {
        guard let raw = quotaResetDateUTC ?? quotaResetDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: String(raw.prefix(10)))
    }

    struct Quotas: Decodable {
        let chat: Int?
        let completions: Int?
    }

    var planLabel: String {
        guard let sku = accessTypeSku else { return "Free" }
        switch sku {
        case "free_limited_copilot": return "Free"
        case "copilot_for_individual", "copilot_individual": return "Individual"
        case "copilot_for_business", "copilot_business": return "Business"
        case "copilot_enterprise": return "Enterprise"
        default:
            // Fall back to copilot_plan field
            if let plan = copilotPlan {
                return plan.prefix(1).uppercased() + plan.dropFirst()
            }
            return "Free"
        }
    }

    enum CodingKeys: String, CodingKey {
        case login
        case accessTypeSku = "access_type_sku"
        case copilotPlan = "copilot_plan"
        case chatEnabled = "chat_enabled"
        case limitedUserQuotas = "limited_user_quotas"
        case limitedUserResetDate = "limited_user_reset_date"
        case monthlyQuotas = "monthly_quotas"
        case quotaSnapshots = "quota_snapshots"
        case quotaResetDate = "quota_reset_date"
        case quotaResetDateUTC = "quota_reset_date_utc"
        case tokenBasedBilling = "token_based_billing"
    }
}

// MARK: - Copilot Keychain (legacy PAT fallback)

/// Separate Keychain service for GitHub PAT storage.
/// Read-only fallback for users who saved a PAT before the gh CLI integration
/// existed; there is no longer any UI to enter a new one.
enum CopilotKeychainService {
    private static let service = "com.robstout.tokenomics.github-pat"
    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CopilotKeychain")

    static func readPAT() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    static func deletePAT() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
