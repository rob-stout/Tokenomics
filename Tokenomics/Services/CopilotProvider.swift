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
    /// Follows VS Code's chatEntitlementService quota parsing.
    nonisolated static func mapToSnapshot(_ info: CopilotUserInfo) -> ProviderUsageSnapshot {
        if info.accessTypeSku == "subscription_ended" {
            return messageSnapshot(info, label: "Copilot", message: "Subscription ended")
        }
        // Free accounts report counted quotas (legacy `monthly_quotas`, or chat /
        // completions snapshots in the 2026 shape); keep that path ahead of paid.
        if info.monthlyQuotas?.chat != nil || info.isFreeViaSnapshots {
            return mapFreeSnapshot(info)
        }
        guard let snapshots = info.quotaSnapshots else {
            // Some Business seats get no quota data at all — say so instead of showing 0%.
            return messageSnapshot(info, label: "Copilot Usage", message: "Usage isn't available for this seat")
        }
        guard let premium = snapshots.premiumInteractions,
              premium.isUnlimited || (premium.entitlement ?? 0) > 0 else {
            return messageSnapshot(info, label: "Copilot Usage", message: "Usage isn't available for this seat")
        }
        return mapPaidSnapshot(info, premium: premium)
    }

    /// A zero-fill bar carrying only a message (no usable usage numbers).
    private nonisolated static func messageSnapshot(
        _ info: CopilotUserInfo,
        label: String,
        message: String
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: label,
                utilization: 0,
                resetsAt: Date.distantFuture,
                windowDuration: 0,
                sublabelOverride: message
            ),
            longWindow: nil,
            planLabel: info.planLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    private nonisolated static func mapFreeSnapshot(_ info: CopilotUserInfo) -> ProviderUsageSnapshot {
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

    /// Paid plans (Pro, Pro+, Max, Business, Enterprise): chat and completions are
    /// unlimited, so the only meter is AI credits (token-based billing, June 2026)
    /// or premium requests (legacy / annual plans).
    private nonisolated static func mapPaidSnapshot(
        _ info: CopilotUserInfo,
        premium: CopilotUserInfo.QuotaSnapshot
    ) -> ProviderUsageSnapshot {
        // The top-level flag is authoritative; per-snapshot `has_quota` is always
        // false under token billing, so it is deliberately not consulted.
        let isTokenBased = info.tokenBasedBilling ?? premium.tokenBasedBilling ?? false
        let label = isTokenBased ? "AI Credits" : "Premium Requests"
        let unit = isTokenBased ? "credits " : ""

        let resetsAt = premium.resetDate ?? info.paidResetDate ?? Date.distantFuture
        let cycleStart = Calendar.current.date(byAdding: .month, value: -1, to: resetsAt) ?? Date()
        let cycleDuration = resetsAt == Date.distantFuture ? 0 : resetsAt.timeIntervalSince(cycleStart)

        let utilization: Double
        let sublabel: String
        if premium.isUnlimited {
            utilization = 0
            // Business/Enterprise seats: no cap, but credits_used is still reported.
            if isTokenBased, let credits = premium.creditsUsed, credits >= 0 {
                sublabel = "\(Int(credits.rounded()).formatted()) credits used"
            } else {
                sublabel = "Unlimited"
            }
        } else {
            let entitlement = premium.entitlement ?? 0
            // percent_remaining is fractional (e.g. 87.3) and more precise than the
            // integer counts. Credits have no denominator of their own, so
            // `credits_used / entitlement` is deliberately never computed.
            let usedPercent: Double
            if let percentRemaining = premium.percentRemaining {
                usedPercent = 100 - percentRemaining
            } else if let remaining = premium.quotaRemaining ?? premium.remaining.map(Double.init) {
                usedPercent = (Double(entitlement) - remaining) / Double(entitlement) * 100
            } else {
                usedPercent = 0
            }
            utilization = max(0, usedPercent)

            let used: Int
            if isTokenBased, let quotaRemaining = premium.quotaRemaining {
                used = Int((Double(entitlement) - quotaRemaining).rounded())
            } else {
                used = Int((Double(entitlement) * utilization / 100).rounded())
            }
            let formatted = isTokenBased
                ? "\(used.formatted()) / \(entitlement.formatted())"
                : "\(used) / \(entitlement)"
            sublabel = "\(formatted) \(unit)used"
        }

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: label,
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

/// Decodes a number that may arrive as a JSON number or a numeric string
/// (`"entitlement": "3900"`). Returns nil when absent or unparseable.
private func decodeFlexibleDouble<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    if let number = try? container.decodeIfPresent(Double.self, forKey: key) { return number }
    if let text = try? container.decodeIfPresent(String.self, forKey: key) { return Double(text) }
    return nil
}

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
        /// -1 means unlimited. Arrives as a number or a string.
        let entitlement: Int?
        let remaining: Int?
        let quotaRemaining: Double?
        let percentRemaining: Double?
        let unlimited: Bool?
        let hasQuota: Bool?
        // Added with token-based billing (June 2026); absent on older responses.
        let tokenBasedBilling: Bool?
        let creditsUsed: Double?
        /// Unix seconds; 0 when unset.
        let quotaResetAt: Double?

        enum CodingKeys: String, CodingKey {
            case entitlement, remaining, unlimited
            case quotaRemaining = "quota_remaining"
            case percentRemaining = "percent_remaining"
            case hasQuota = "has_quota"
            case tokenBasedBilling = "token_based_billing"
            case creditsUsed = "credits_used"
            case quotaResetAt = "quota_reset_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entitlement = decodeFlexibleDouble(c, .entitlement).map { Int($0) }
            remaining = decodeFlexibleDouble(c, .remaining).map { Int($0) }
            quotaRemaining = decodeFlexibleDouble(c, .quotaRemaining)
            percentRemaining = decodeFlexibleDouble(c, .percentRemaining)
            creditsUsed = decodeFlexibleDouble(c, .creditsUsed)
            quotaResetAt = decodeFlexibleDouble(c, .quotaResetAt)
            unlimited = try? c.decodeIfPresent(Bool.self, forKey: .unlimited)
            hasQuota = try? c.decodeIfPresent(Bool.self, forKey: .hasQuota)
            tokenBasedBilling = try? c.decodeIfPresent(Bool.self, forKey: .tokenBasedBilling)
        }

        var isUnlimited: Bool { unlimited == true || entitlement == -1 }

        /// Snapshot reset time, when the server sets one (> 0).
        var resetDate: Date? {
            guard let raw = quotaResetAt, raw > 0 else { return nil }
            // Tolerate milliseconds just in case.
            return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1000 : raw)
        }
    }

    /// Free accounts in the 2026 response shape: no premium quota, but counted
    /// chat/completions snapshots. Also covers the free SKUs explicitly.
    var isFreeViaSnapshots: Bool {
        if accessTypeSku == "free_limited_copilot" || accessTypeSku == "free_educational_quota" {
            return (quotaSnapshots?.chat?.entitlement ?? 0) > 0
        }
        guard let snaps = quotaSnapshots,
              let premium = snaps.premiumInteractions,
              !premium.isUnlimited, (premium.entitlement ?? 0) <= 0,
              let chat = snaps.chat, !chat.isUnlimited,
              (chat.entitlement ?? 0) > 0 else { return false }
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
        if accessTypeSku == "free_limited_copilot" || accessTypeSku == "free_educational_quota" { return "Free" }
        if accessTypeSku == "subscription_ended" { return "Subscription ended" }
        switch copilotPlan?.lowercased() {
        case "individual": return "Pro"
        case "individual_pro": return "Pro+"
        case "individual_max": return "Max"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "individual_edu": return "Edu"
        default: break
        }
        switch accessTypeSku {
        case "copilot_for_business", "copilot_business": return "Business"
        case "copilot_enterprise": return "Enterprise"
        case "copilot_for_individual", "copilot_individual": return "Pro"
        default:
            if let plan = copilotPlan, !plan.isEmpty {
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
