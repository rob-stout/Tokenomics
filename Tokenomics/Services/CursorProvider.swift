import AppKit
import Foundation
import os

/// Cursor IDE usage provider — reads auth from local SQLite, fetches usage from cursor.com API.
///
/// Auth flow: reads JWT from `state.vscdb` (Cursor's local storage), extracts the user ID
/// from the JWT `sub` claim, then builds a session cookie for the cursor.com API.
///
/// API: `GET https://cursor.com/api/usage-summary` — returns premium request usage,
/// billing cycle dates, and plan type.
actor CursorProvider: UsageProvider {
    let id = ProviderId.cursor
    let pollInterval: TimeInterval = 300 // 5 min — remote API but local token read

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CursorProvider")

    private static let stateDBPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }()

    /// Cursor's app bundle identifier — shared with `CursorConnector`, which
    /// uses the same lookup to locate and launch the installed app for its
    /// "Open Cursor" sign-in CTA. Defined once here to avoid drift.
    static let bundleIdentifier = "com.todesktop.230313mzl4w4u92"

    /// Cached user ID extracted from JWT to avoid re-parsing every poll
    private var cachedUserId: String?

    func checkConnection() async -> ProviderConnectionState {
        if let forced = DetectionScenario.current.forcedConnection { return forced }
        guard isCursorInstalled() else { return .notInstalled }
        guard let token = readAccessToken() else { return .installedNoAuth }

        do {
            let userId = try extractUserId(from: token)
            cachedUserId = userId
            let summary = try await fetchUsageSummary(token: token, userId: userId)
            return .connected(plan: summary.planLabel)
        } catch {
            Self.log.warning("Cursor connection check failed: \(error.localizedDescription)")
            return .installedNoAuth
        }
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        guard let token = readAccessToken() else {
            throw AppError.notAuthenticated
        }

        let userId: String
        if let cached = cachedUserId {
            userId = cached
        } else {
            userId = try extractUserId(from: token)
            cachedUserId = userId
        }

        let summary = try await fetchUsageSummary(token: token, userId: userId)
        if summary.isUnified {
            // After the Cursor/X/Grok unification, usage-summary's plan numbers go stale
            // (it can report 0), so read the weekly pool from the dashboard service.
            let usage = try await fetchCurrentPeriodUsage(token: token)
            let plan = try await fetchPlanInfo(token: token)
            return Self.mapUnifiedSnapshot(summary: summary, usage: usage, plan: plan)
        }
        return Self.mapToSnapshot(summary)
    }

    // MARK: - SQLite Token Reading

    /// Read the access token from Cursor's local SQLite database
    private func readAccessToken() -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.stateDBPath) else { return nil }

        // Use sqlite3 CLI to avoid linking libsqlite3
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [Self.stateDBPath, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken';"]

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
            Self.log.error("Failed to read Cursor state.vscdb: \(error.localizedDescription)")
            return nil
        }
    }

    /// Extract the user ID from a JWT's `sub` claim (e.g. "auth0|12345678")
    private func extractUserId(from jwt: String) throws -> String {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else {
            throw AppError.decodingFailed(underlying: CursorError.invalidJWT)
        }

        // Base64url decode the payload segment
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            throw AppError.decodingFailed(underlying: CursorError.missingSubClaim)
        }
        return sub
    }

    private func isCursorInstalled() -> Bool {
        let paths = [
            "/Applications/Cursor.app",
            Self.stateDBPath
        ]
        if paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            return true
        }

        // Fast-path checks above miss a Cursor install outside /Applications
        // (e.g. ~/Applications) that has never been launched — state.vscdb
        // doesn't exist yet either in that case. Launch Services still knows
        // about it once it's been installed, so ask it directly.
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
    }

    // MARK: - Cursor API

    private func fetchUsageSummary(token: String, userId: String) async throws -> CursorUsageSummary {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WorkosCursorSessionToken=\(userId)::\(token)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(CursorUsageSummary.self, from: data)
    }

    /// Connect-protocol JSON POST, same shape openusage uses: bearer token,
    /// `Connect-Protocol-Version: 1`, empty `{}` body.
    private func connectPost<T: Decodable>(_ method: String, token: String, as type: T.Type) async throws -> T {
        let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/\(method)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AppError.decodingFailed(underlying: error)
        }
    }

    private func fetchCurrentPeriodUsage(token: String) async throws -> CursorCurrentPeriodUsage {
        try await connectPost("GetCurrentPeriodUsage", token: token, as: CursorCurrentPeriodUsage.self)
    }

    private func fetchPlanInfo(token: String) async throws -> CursorPlanInfoResponse {
        try await connectPost("GetPlanInfo", token: token, as: CursorPlanInfoResponse.self)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401, 403: throw AppError.tokenExpired
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw AppError.rateLimited(retryAfter: retryAfter)
        default:
            throw AppError.httpError(statusCode: http.statusCode)
        }
    }

    // MARK: - Helpers

    /// Returns the billing cycle duration when both endpoints are known.
    /// Without `start`, cycleDuration would equal remaining time and pace
    /// would always read 0 — so returns 0 to hide the dot honestly.
    static func cycleDuration(start: Date?, end: Date?) -> TimeInterval {
        guard let start, let end else { return 0 }
        return end.timeIntervalSince(start)
    }

    // MARK: - Mapping

    /// One shared weekly pool for unified Cursor/X/Grok accounts. The monthly bars
    /// are intentionally absent: after unification they no longer mean anything.
    nonisolated static func mapUnifiedSnapshot(
        summary: CursorUsageSummary,
        usage: CursorCurrentPeriodUsage,
        plan: CursorPlanInfoResponse
    ) -> ProviderUsageSnapshot {
        let percent = max(0, usage.planUsage?.totalPercentUsed ?? 0)
        let resetsAt = plan.planInfo?.includedUsageResetsAt
            ?? usage.billingCycleEnd
            ?? Date.distantFuture
        let hasReset = resetsAt != Date.distantFuture
        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Weekly Usage",
                utilization: min(percent, 999),
                resetsAt: resetsAt,
                windowDuration: hasReset ? 7 * 24 * 3600 : 0,
                sublabelOverride: String(format: "%.1f%% of weekly allowance used", percent)
            ),
            longWindow: nil,
            planLabel: summary.planLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    nonisolated static func mapToSnapshot(_ summary: CursorUsageSummary) -> ProviderUsageSnapshot {
        let plan = summary.individualUsage?.plan
        let used = plan?.used ?? 0
        let limit = plan?.breakdown?.total ?? plan?.limit ?? 0

        // Use server-computed percentage when available, fall back to manual calc
        let utilization: Double
        if let serverPercent = plan?.totalPercentUsed, serverPercent > 0 {
            utilization = serverPercent
        } else if limit > 0 {
            utilization = Double(used) / Double(limit) * 100
        } else {
            utilization = 0
        }

        let resetsAt = summary.billingCycleEnd ?? Date.distantFuture
        let cycleDuration = Self.cycleDuration(start: summary.billingCycleStart, end: summary.billingCycleEnd)

        // Build sublabel from actual data
        let sublabel: String
        if limit > 0 {
            sublabel = "\(used) / \(limit) used"
        } else if let message = summary.autoModelSelectedDisplayMessage {
            // Free tier: server provides a readable message
            sublabel = message
        } else {
            sublabel = "\(used) requests used"
        }

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Premium Requests",
                utilization: min(utilization, 999),
                resetsAt: resetsAt,
                windowDuration: cycleDuration,
                sublabelOverride: sublabel
            ),
            longWindow: nil,
            planLabel: summary.planLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }
}

// MARK: - Response Models

/// Connect/gRPC-JSON int64 fields arrive as strings ("1795333076119"); accept numbers too.
private func decodeMillis<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Date? {
    guard let ms: Double = {
        if let s = try? container.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        if let n = try? container.decodeIfPresent(Double.self, forKey: key) { return n }
        return nil
    }() else { return nil }
    return Date(timeIntervalSince1970: ms / 1000)
}

/// `POST GetCurrentPeriodUsage` — `planUsage.totalPercentUsed` is already a percent.
struct CursorCurrentPeriodUsage: Decodable {
    let billingCycleEnd: Date?
    let planUsage: PlanUsage?

    struct PlanUsage: Decodable {
        let totalPercentUsed: Double?
    }

    enum CodingKeys: String, CodingKey { case billingCycleEnd, planUsage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        billingCycleEnd = decodeMillis(c, CodingKeys.billingCycleEnd)
        planUsage = try c.decodeIfPresent(PlanUsage.self, forKey: .planUsage)
    }
}

/// `POST GetPlanInfo` — `isMerged` marks a unified account.
struct CursorPlanInfoResponse: Decodable {
    let isMerged: Bool?
    let planInfo: PlanInfo?

    struct PlanInfo: Decodable {
        let planName: String?
        let includedUsagePeriod: String?
        let includedUsageResetsAt: Date?

        enum CodingKeys: String, CodingKey { case planName, includedUsagePeriod, includedUsageResetsAt }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            planName = try c.decodeIfPresent(String.self, forKey: .planName)
            includedUsagePeriod = try c.decodeIfPresent(String.self, forKey: .includedUsagePeriod)
            includedUsageResetsAt = decodeMillis(c, CodingKeys.includedUsageResetsAt)
        }
    }
}

struct CursorUsageSummary: Decodable {
    let membershipType: String?
    let isUnlimited: Bool?
    let individualUsage: IndividualUsage?
    let billingCycleStart: Date?
    let billingCycleEnd: Date?
    let autoModelSelectedDisplayMessage: String?

    struct IndividualUsage: Decodable {
        let plan: PlanUsage?
        let onDemand: OnDemandUsage?
    }

    struct PlanUsage: Decodable {
        let enabled: Bool?
        let used: Int
        let limit: Int
        let remaining: Int?
        let breakdown: Breakdown?
        let totalPercentUsed: Double?

        struct Breakdown: Decodable {
            let included: Int?
            let bonus: Int?
            let total: Int?
        }
    }

    struct OnDemandUsage: Decodable {
        let enabled: Bool?
        let used: Int?
        let limit: Int?
    }

    /// "X Subscription" accounts report e.g. "unified_ultra".
    var isUnified: Bool {
        membershipType?.lowercased().hasPrefix("unified") == true
    }

    var planLabel: String {
        guard var membership = membershipType else { return "Free" }
        if isUnified { membership = String(membership.dropFirst("unified_".count)) }
        switch membership.lowercased() {
        case "free": return "Free"
        case "pro": return "Pro"
        case "business": return "Business"
        case "ultra": return "Ultra"
        default: return membership.prefix(1).uppercased() + membership.dropFirst()
        }
    }

    enum CodingKeys: String, CodingKey {
        case membershipType, isUnlimited, individualUsage
        case billingCycleStart, billingCycleEnd
        case autoModelSelectedDisplayMessage
    }

    /// Memberwise init for tests.
    init(membershipType: String?, isUnlimited: Bool? = nil) {
        self.membershipType = membershipType
        self.isUnlimited = isUnlimited
        individualUsage = nil
        billingCycleStart = nil
        billingCycleEnd = nil
        autoModelSelectedDisplayMessage = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        membershipType = try container.decodeIfPresent(String.self, forKey: .membershipType)
        isUnlimited = try container.decodeIfPresent(Bool.self, forKey: .isUnlimited)
        individualUsage = try container.decodeIfPresent(IndividualUsage.self, forKey: .individualUsage)
        autoModelSelectedDisplayMessage = try container.decodeIfPresent(String.self, forKey: .autoModelSelectedDisplayMessage)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        if let startStr = try container.decodeIfPresent(String.self, forKey: .billingCycleStart) {
            billingCycleStart = formatter.date(from: startStr) ?? fallback.date(from: startStr)
        } else {
            billingCycleStart = nil
        }

        if let endStr = try container.decodeIfPresent(String.self, forKey: .billingCycleEnd) {
            billingCycleEnd = formatter.date(from: endStr) ?? fallback.date(from: endStr)
        } else {
            billingCycleEnd = nil
        }
    }
}

private enum CursorError: Error, LocalizedError {
    case invalidJWT
    case missingSubClaim

    var errorDescription: String? {
        switch self {
        case .invalidJWT: return "Invalid Cursor auth token format"
        case .missingSubClaim: return "Could not extract user ID from Cursor token"
        }
    }
}
