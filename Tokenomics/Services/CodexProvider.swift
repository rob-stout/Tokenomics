import Foundation

/// Codex CLI usage provider — reads local JSONL session files (no network needed)
actor CodexProvider: UsageProvider {
    let id = ProviderId.codex

    private let codexDir: URL
    private let sessionsDir: URL
    private let authFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.codexDir = home.appendingPathComponent(".codex")
        self.sessionsDir = codexDir.appendingPathComponent("sessions")
        self.authFile = codexDir.appendingPathComponent("auth.json")
    }

    func checkConnection() async -> ProviderConnectionState {
        let fm = FileManager.default

        // Check if Codex CLI is installed
        guard fm.fileExists(atPath: codexDir.path) || isCodexInPath() else {
            return .notInstalled
        }

        // Check for auth
        guard fm.fileExists(atPath: authFile.path) else {
            return .installedNoAuth
        }

        // Verify auth.json has a token
        guard let authData = try? Data(contentsOf: authFile),
              let auth = try? JSONDecoder().decode(CodexAuth.self, from: authData),
              !auth.accessToken.isEmpty else {
            return .installedNoAuth
        }

        // Try to read usage data to confirm everything works
        if let snapshot = try? await fetchUsage() {
            return .connected(plan: snapshot.planLabel)
        }

        // Auth exists but no session data yet — still connected
        return .connected(plan: "—")
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let sessionData = findLatestSessionData()

        guard let sessionData else {
            throw AppError.decodingFailed(underlying: CodexError.noSessionData)
        }

        return mapToSnapshot(sessionData)
    }

    // MARK: - JSONL Parsing

    /// Combined data from the most recent session's token_count event
    private struct SessionData {
        let tokenCount: CodexTokenCount?
        let rateLimits: CodexRateLimits?
    }

    /// Finds the most recent token_count and rate_limits entries across session files
    private func findLatestSessionData() -> SessionData? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: sessionsDir.path) else { return nil }

        guard let yearDirs = try? fm.contentsOfDirectory(atPath: sessionsDir.path)
            .sorted(by: >) else { return nil }

        for year in yearDirs {
            let yearPath = sessionsDir.appendingPathComponent(year)
            guard let monthDirs = try? fm.contentsOfDirectory(atPath: yearPath.path)
                .sorted(by: >) else { continue }

            for month in monthDirs {
                let monthPath = yearPath.appendingPathComponent(month)
                guard let dayDirs = try? fm.contentsOfDirectory(atPath: monthPath.path)
                    .sorted(by: >) else { continue }

                for day in dayDirs {
                    let dayPath = monthPath.appendingPathComponent(day)
                    guard let sessionFiles = try? fm.contentsOfDirectory(atPath: dayPath.path)
                        .filter({ $0.hasSuffix(".jsonl") })
                        .sorted(by: >) else { continue }

                    for file in sessionFiles {
                        let filePath = dayPath.appendingPathComponent(file)
                        if let data = parseLastSessionData(from: filePath) {
                            return data
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Reads the tail of a JSONL file and extracts the last token_count and rate_limits.
    /// Only reads the last ~16KB to avoid loading entire large session files.
    private func parseLastSessionData(from url: URL) -> SessionData? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 0 else { return nil }

        // Read tail — token_count events can be larger than rate_limits
        let readSize = min(fileSize, 16384)
        handle.seek(toFileOffset: fileSize - readSize)
        let tailData = handle.readData(ofLength: Int(readSize))

        guard let content = String(data: tailData, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines).reversed()
        let decoder = JSONDecoder()

        var tokenCount: CodexTokenCount?
        var rateLimits: CodexRateLimits?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Look for token_count events (contain context window data)
            if tokenCount == nil && trimmed.contains("token_count") {
                if let lineData = trimmed.data(using: .utf8),
                   let event = try? decoder.decode(CodexTokenCountEvent.self, from: lineData),
                   let tc = event.tokenCount {
                    tokenCount = tc
                }
            }

            // Look for rate_limits (still useful for plan_type and reset times)
            if rateLimits == nil && trimmed.contains("rate_limits") {
                if let lineData = trimmed.data(using: .utf8),
                   let event = try? decoder.decode(CodexSessionEvent.self, from: lineData),
                   let rl = event.rateLimits {
                    rateLimits = rl
                }
            }

            // Found both — stop scanning
            if tokenCount != nil && rateLimits != nil { break }
        }

        // Need at least one source of data
        guard tokenCount != nil || rateLimits != nil else { return nil }

        return SessionData(tokenCount: tokenCount, rateLimits: rateLimits)
    }

    private func isCodexInPath() -> Bool {
        let commonPaths = [
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
            "/opt/homebrew/bin/codex"
        ]
        return commonPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func mapToSnapshot(_ data: SessionData) -> ProviderUsageSnapshot {
        // Primary bar: Context Window usage (what CLI shows as "% left")
        let shortWindow: WindowUsage
        if let tc = data.tokenCount {
            let contextUsed = Double(tc.lastInputTokens) / Double(tc.modelContextWindow) * 100
            let remaining = tc.modelContextWindow - tc.lastInputTokens
            let sublabel = "\(Self.formatTokens(remaining)) of \(Self.formatTokens(tc.modelContextWindow)) remaining"
            shortWindow = WindowUsage(
                label: "Context Window",
                utilization: contextUsed,
                resetsAt: Date.distantFuture,
                windowDuration: 1,
                sublabelOverride: sublabel
            )
        } else {
            // Fall back to rate limit primary if no token_count data
            let primary = data.rateLimits?.primary
            shortWindow = WindowUsage(
                label: "5-Hour Window",
                utilization: primary?.usedPercent ?? 0,
                resetsAt: Date(timeIntervalSince1970: primary?.resetsAt ?? 0),
                windowDuration: Double(primary?.windowMinutes ?? 300) * 60
            )
        }

        // Secondary bar: Rate limit 5-hour window (currently 0% but will auto-fix)
        let longWindow: WindowUsage
        if let primary = data.rateLimits?.primary {
            longWindow = WindowUsage(
                label: "5-Hour Window",
                utilization: primary.usedPercent,
                resetsAt: Date(timeIntervalSince1970: primary.resetsAt),
                windowDuration: Double(primary.windowMinutes) * 60
            )
        } else {
            longWindow = WindowUsage(
                label: "5-Hour Window",
                utilization: 0,
                resetsAt: Date.distantFuture,
                windowDuration: 300 * 60
            )
        }

        let plan = inferPlan(from: data.rateLimits)

        return ProviderUsageSnapshot(
            shortWindow: shortWindow,
            longWindow: longWindow,
            planLabel: plan,
            extraUsage: nil,
            creditsBalance: data.rateLimits?.credits?.balance
        )
    }

    /// Formats token counts for display (e.g. 230,681 → "230.7K", 258,400 → "258.4K")
    private static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func inferPlan(from limits: CodexRateLimits?) -> String {
        guard let limits else { return "Free" }
        // Prefer explicit plan_type (newer Codex versions)
        if let planType = limits.planType, !planType.isEmpty {
            return planType.prefix(1).uppercased() + planType.dropFirst()
        }
        // Fall back to credits-based inference
        guard let credits = limits.credits else { return "Free" }
        if credits.unlimited { return "Pro" }
        if credits.hasCredits { return "Plus" }
        return "Free"
    }
}

// MARK: - Codex Data Models

private enum CodexError: Error {
    case noSessionData
}

/// Codex auth.json nests the token: `{ "tokens": { "access_token": "..." } }`
private struct CodexAuth: Decodable {
    let accessToken: String

    private enum RootKeys: String, CodingKey {
        case tokens
    }

    private enum TokenKeys: String, CodingKey {
        case accessToken = "access_token"
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let tokens = try root.nestedContainer(keyedBy: TokenKeys.self, forKey: .tokens)
        self.accessToken = try tokens.decode(String.self, forKey: .accessToken)
    }
}

/// Decodes a token_count event from JSONL:
/// `{ "type": "event_msg", "payload": { "type": "token_count", "info": { ... } } }`
private struct CodexTokenCountEvent: Decodable {
    let tokenCount: CodexTokenCount?

    private enum CodingKeys: String, CodingKey {
        case payload
    }

    private enum PayloadKeys: String, CodingKey {
        case type, info
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let payload = try? container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload) {
            let type = try? payload.decode(String.self, forKey: .type)
            if type == "token_count" {
                self.tokenCount = try? payload.decode(CodexTokenCount.self, forKey: .info)
            } else {
                self.tokenCount = nil
            }
        } else {
            self.tokenCount = nil
        }
    }
}

/// Token usage from a token_count event's `info` field
struct CodexTokenCount: Decodable, Sendable {
    let lastInputTokens: Int
    let modelContextWindow: Int

    private enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case modelContextWindow = "model_context_window"
    }

    private enum UsageKeys: String, CodingKey {
        case inputTokens = "input_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.modelContextWindow = try container.decode(Int.self, forKey: .modelContextWindow)
        let usage = try container.nestedContainer(keyedBy: UsageKeys.self, forKey: .lastTokenUsage)
        self.lastInputTokens = try usage.decode(Int.self, forKey: .inputTokens)
    }
}

/// A single line in a Codex session JSONL file.
/// Rate limits are nested: `{ "type": "event_msg", "payload": { "rate_limits": { ... } } }`
private struct CodexSessionEvent: Decodable {
    let rateLimits: CodexRateLimits?

    private enum CodingKeys: String, CodingKey {
        case payload
    }

    private enum PayloadKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let payload = try? container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload) {
            self.rateLimits = try? payload.decode(CodexRateLimits.self, forKey: .rateLimits)
        } else {
            self.rateLimits = nil
        }
    }
}

struct CodexRateLimits: Decodable, Sendable {
    let primary: CodexRateLimitWindow
    let secondary: CodexRateLimitWindow
    let credits: CodexCredits?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary, secondary, credits
        case planType = "plan_type"
    }
}

struct CodexRateLimitWindow: Decodable, Sendable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Double

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

struct CodexCredits: Decodable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}
