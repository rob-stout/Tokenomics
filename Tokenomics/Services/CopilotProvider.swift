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
        let chatQuota = info.limitedUserQuotas?.chat ?? 0
        let chatLimit = info.monthlyQuotas?.chat ?? 0
        let chatUsed = chatLimit - chatQuota

        let completionsQuota = info.limitedUserQuotas?.completions ?? 0
        let completionsLimit = info.monthlyQuotas?.completions ?? 0
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
}

// MARK: - Response Model

private struct CopilotUserInfo: Decodable {
    let login: String?
    let accessTypeSku: String?
    let copilotPlan: String?
    let chatEnabled: Bool?
    let limitedUserQuotas: Quotas?
    let limitedUserResetDate: String?
    let monthlyQuotas: Quotas?

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
