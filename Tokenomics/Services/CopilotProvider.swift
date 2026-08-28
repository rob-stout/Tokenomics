import Foundation
import os

/// GitHub Copilot usage provider — zero-friction auth via `gh` CLI token.
///
/// Auth: reads the token from `gh auth token` (stored in the system keyring by
/// the GitHub CLI). No PAT or manual setup required.
///
/// API: `GET https://api.github.com/copilot_internal/user` — returns the user's
/// plan, quota reset date, and per-quota snapshots. We surface the
/// `quota_snapshots.premium_interactions` metric (the AI credits budget).
actor CopilotProvider: UsageProvider {
    let id = ProviderId.copilot
    let pollInterval: TimeInterval = 300 // 5 min — lightweight internal endpoint

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CopilotProvider")

    func checkConnection() async -> ProviderConnectionState {
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
        return mapToSnapshot(userInfo)
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

    private func mapToSnapshot(_ info: CopilotUserInfo) -> ProviderUsageSnapshot {
        let resetsAt = info.resetDate ?? Date.distantFuture

        // Estimate cycle start (reset date minus ~1 month) for pace calculations.
        let calendar = Calendar.current
        let cycleStart = calendar.date(byAdding: .month, value: -1, to: resetsAt) ?? Date()
        let cycleDuration = resetsAt.timeIntervalSince(cycleStart)

        let premium = info.quotaSnapshots?.premiumInteractions
        let shortWindow = premiumWindow(premium, resetsAt: resetsAt, windowDuration: cycleDuration)

        return ProviderUsageSnapshot(
            shortWindow: shortWindow,
            longWindow: nil,
            planLabel: info.planLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    private func premiumWindow(_ snapshot: CopilotUserInfo.QuotaSnapshot?,
                               resetsAt: Date,
                               windowDuration: TimeInterval) -> WindowUsage {
        let label = "AI credits"

        guard let snapshot, !(snapshot.unlimited ?? false) else {
            return WindowUsage(
                label: label,
                utilization: 0,
                resetsAt: resetsAt,
                windowDuration: windowDuration,
                sublabelOverride: "Unlimited"
            )
        }

        let entitlement = snapshot.entitlement ?? 0
        let remaining = snapshot.remaining ?? entitlement
        let used = max(entitlement - remaining, 0)

        // Prefer the server-provided percentage; fall back to a local calc.
        let utilization: Double
        if let percentRemaining = snapshot.percentRemaining {
            utilization = max(0, 100 - percentRemaining)
        } else if entitlement > 0 {
            utilization = Double(used) / Double(entitlement) * 100
        } else {
            utilization = 0
        }

        let sublabel = "\(Self.formatCount(used)) / \(Self.formatCount(entitlement)) used"

        return WindowUsage(
            label: label,
            utilization: min(utilization, 999),
            resetsAt: resetsAt,
            windowDuration: windowDuration,
            sublabelOverride: sublabel
        )
    }

    private static func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Response Model

private struct CopilotUserInfo: Decodable {
    let login: String?
    let accessTypeSku: String?
    let copilotPlan: String?
    let chatEnabled: Bool?
    let quotaSnapshots: QuotaSnapshots?
    let quotaResetDate: String?
    let quotaResetDateUtc: String?

    struct QuotaSnapshots: Decodable {
        let premiumInteractions: QuotaSnapshot?

        enum CodingKeys: String, CodingKey {
            case premiumInteractions = "premium_interactions"
        }
    }

    struct QuotaSnapshot: Decodable {
        let entitlement: Int?
        let remaining: Int?
        let percentRemaining: Double?
        let unlimited: Bool?
        let overageCount: Int?
        let overagePermitted: Bool?

        enum CodingKeys: String, CodingKey {
            case entitlement
            case remaining
            case percentRemaining = "percent_remaining"
            case unlimited
            case overageCount = "overage_count"
            case overagePermitted = "overage_permitted"
        }
    }

    /// Reset date for the current quota cycle. Prefers the precise UTC timestamp,
    /// falling back to the day-granularity `quota_reset_date`.
    var resetDate: Date? {
        if let utc = quotaResetDateUtc, let date = Self.iso8601.date(from: utc) {
            return date
        }
        if let day = quotaResetDate, let date = Self.dayFormatter.date(from: day) {
            return date
        }
        return nil
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var planLabel: String {
        if let sku = accessTypeSku?.lowercased() {
            if sku.contains("free") { return "Free" }
            if sku.contains("enterprise") { return "Enterprise" }
            if sku.contains("business") { return "Business" }
            if sku.contains("individual") { return "Individual" }
        }
        if let plan = copilotPlan, !plan.isEmpty {
            return plan.prefix(1).uppercased() + plan.dropFirst()
        }
        return "Free"
    }

    enum CodingKeys: String, CodingKey {
        case login
        case accessTypeSku = "access_type_sku"
        case copilotPlan = "copilot_plan"
        case chatEnabled = "chat_enabled"
        case quotaSnapshots = "quota_snapshots"
        case quotaResetDate = "quota_reset_date"
        case quotaResetDateUtc = "quota_reset_date_utc"
    }
}

// MARK: - Copilot Keychain (legacy PAT fallback)

/// Separate Keychain service for GitHub PAT storage.
/// Kept as a fallback for users who manually entered a PAT before the
/// zero-friction gh CLI integration was added.
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

    static func savePAT(_ token: String) {
        deletePAT()

        guard let data = token.data(using: .utf8) else { return }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Failed to save GitHub PAT: \(status)")
        }
    }

    static func deletePAT() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
