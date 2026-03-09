import Foundation
import os

/// GitHub Copilot usage provider — fetches premium request usage via GitHub REST API.
///
/// Auth: Fine-grained Personal Access Token with "Plan" read permission,
/// stored in our Keychain. Falls back to reading the GitHub CLI token from
/// `~/.config/gh/hosts.yml` if present.
///
/// API: `GET /users/{username}/settings/billing/premium_request/usage`
/// Returns billing line items for the current month. The limit (e.g. 300 for
/// Individual) is not exposed, so we hardcode known plan tiers.
actor CopilotProvider: UsageProvider {
    let id = ProviderId.copilot
    let pollInterval: TimeInterval = 600 // 10 min — remote API

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CopilotProvider")

    /// Cached username to avoid re-fetching on every poll
    private var cachedUsername: String?

    func checkConnection() async -> ProviderConnectionState {
        guard let token = readToken() else {
            if isGitHubCLIInstalled() { return .installedNoAuth }
            return .notInstalled
        }

        // Validate token with a lightweight /user call
        do {
            let username = try await fetchUsername(token: token)
            cachedUsername = username

            // Try billing to detect plan; if it fails, still show connected
            if let usage = try? await fetchBillingUsage(token: token, username: username) {
                let plan = inferPlan(from: usage)
                return .connected(plan: plan)
            }
            return .connected(plan: "Free")
        } catch {
            Self.log.warning("Copilot connection check failed: \(error.localizedDescription)")
            return .installedNoAuth
        }
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        guard let token = readToken() else {
            throw AppError.notAuthenticated
        }

        let username: String
        if let cached = cachedUsername {
            username = cached
        } else {
            username = try await fetchUsername(token: token)
            cachedUsername = username
        }

        do {
            let usage = try await fetchBillingUsage(token: token, username: username)
            return mapToSnapshot(usage)
        } catch AppError.httpError(statusCode: 404) {
            // 404 means the token lacks "Plan" scope or user is on free tier
            // with no billing data. Return a snapshot indicating PAT is needed.
            return noBillingDataSnapshot()
        }
    }

    /// Snapshot shown when the billing endpoint isn't accessible (wrong scope or free plan)
    private func noBillingDataSnapshot() -> ProviderUsageSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        let resetsAt = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) ?? now
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Premium Requests",
                utilization: 0,
                resetsAt: resetsAt,
                windowDuration: resetsAt.timeIntervalSince(monthStart),
                sublabelOverride: "Add a PAT with Plan scope for usage data"
            ),
            longWindow: nil,
            planLabel: "Free",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // MARK: - Token Reading

    /// Read the GitHub PAT — checks our Keychain first, then `gh auth token` CLI
    private func readToken() -> String? {
        if let pat = CopilotKeychainService.readPAT() {
            return pat
        }
        return readGitHubCLIToken()
    }

    /// Read token via `gh auth token` (gh stores tokens in the system keyring)
    private func readGitHubCLIToken() -> String? {
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

    // MARK: - GitHub API

    /// Fetch the authenticated user's login name
    private func fetchUsername(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.addGitHubHeaders(token: token)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        struct UserResponse: Decodable {
            let login: String
        }
        let user = try JSONDecoder().decode(UserResponse.self, from: data)
        return user.login
    }

    /// Fetch premium request billing for the current month
    private func fetchBillingUsage(token: String, username: String) async throws -> CopilotBillingResponse {
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        var components = URLComponents(string: "https://api.github.com/users/\(username)/settings/billing/premium_request/usage")!
        components.queryItems = [
            URLQueryItem(name: "year", value: "\(year)"),
            URLQueryItem(name: "month", value: "\(month)")
        ]

        var request = URLRequest(url: components.url!)
        request.addGitHubHeaders(token: token)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(CopilotBillingResponse.self, from: data)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401: throw AppError.tokenExpired
        case 403: throw AppError.tokenExpired // PAT lacks required permission
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw AppError.rateLimited(retryAfter: retryAfter)
        default:
            throw AppError.httpError(statusCode: http.statusCode)
        }
    }

    // MARK: - Mapping

    private func mapToSnapshot(_ billing: CopilotBillingResponse) -> ProviderUsageSnapshot {
        // Sum premium requests across all models
        let totalUsed = billing.usageItems
            .filter { $0.sku == "Copilot Premium Request" }
            .reduce(0) { $0 + $1.grossQuantity }

        // Known plan limits — GitHub doesn't expose these via API
        let limit = inferLimit(from: billing)
        let utilization = limit > 0 ? Double(totalUsed) / Double(limit) * 100 : 0

        // Monthly reset: 1st of next month
        let calendar = Calendar.current
        let now = Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        let resetsAt = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) ?? now
        let monthDuration = resetsAt.timeIntervalSince(
            calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        )

        let plan = inferPlan(from: billing)

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Premium Requests",
                utilization: min(utilization, 999),
                resetsAt: resetsAt,
                windowDuration: monthDuration,
                sublabelOverride: "\(totalUsed) / \(limit) used"
            ),
            longWindow: nil,
            planLabel: plan,
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    /// Infer plan tier from billing data
    private func inferPlan(from billing: CopilotBillingResponse) -> String {
        let totalUsed = billing.usageItems
            .filter { $0.sku == "Copilot Premium Request" }
            .reduce(0) { $0 + $1.grossQuantity }

        // If they have premium request usage, they're at least on Individual
        // We can't reliably distinguish Pro from Individual via billing alone
        if totalUsed > 0 { return "Individual" }
        return "Free"
    }

    /// Known premium request limits per plan
    private func inferLimit(from billing: CopilotBillingResponse) -> Int {
        // GitHub Individual: 300/month, Pro: higher limits
        // Default to Individual limit since we can't detect the plan tier
        return SettingsService.copilotMonthlyLimit ?? 300
    }
}

// MARK: - GitHub API Helpers

private extension URLRequest {
    mutating func addGitHubHeaders(token: String) {
        setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    }
}

// MARK: - Response Models

struct CopilotBillingResponse: Decodable, Sendable {
    let usageItems: [CopilotUsageItem]

    enum CodingKeys: String, CodingKey {
        case usageItems = "usageItems"
    }
}

struct CopilotUsageItem: Decodable, Sendable {
    let product: String
    let sku: String
    let model: String
    let unitType: String
    let pricePerUnit: Double
    let grossQuantity: Int
    let grossAmount: Double

    enum CodingKeys: String, CodingKey {
        case product, sku, model, unitType, pricePerUnit
        case grossQuantity, grossAmount
    }
}

// MARK: - Copilot Keychain

/// Separate Keychain service for GitHub PAT storage
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
        // Delete existing entry first
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
