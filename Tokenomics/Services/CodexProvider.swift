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
        guard let rateLimits = findLatestRateLimits() else {
            throw AppError.decodingFailed(underlying: CodexError.noSessionData)
        }

        return mapToSnapshot(rateLimits)
    }

    // MARK: - JSONL Parsing

    /// Finds the most recent rate_limits entry across all session JSONL files
    private func findLatestRateLimits() -> CodexRateLimits? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: sessionsDir.path) else { return nil }

        // Walk sessions directory: sessions/YYYY/MM/DD/<session>.jsonl
        // Sort by date directory names (descending) to find most recent first
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
                        if let limits = parseLastRateLimits(from: filePath) {
                            return limits
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Reads the tail of a JSONL file and returns the last rate_limits entry.
    /// Only reads the last ~8KB to avoid loading entire large session files.
    private func parseLastRateLimits(from url: URL) -> CodexRateLimits? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 0 else { return nil }

        // Read only the tail — rate_limits entries are a few hundred bytes each
        let readSize = min(fileSize, 8192)
        handle.seek(toFileOffset: fileSize - readSize)
        let tailData = handle.readData(ofLength: Int(readSize))

        guard let content = String(data: tailData, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines).reversed()
        let decoder = JSONDecoder()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Quick check before full JSON parse
            guard trimmed.contains("rate_limits") else { continue }

            guard let lineData = trimmed.data(using: .utf8),
                  let event = try? decoder.decode(CodexSessionEvent.self, from: lineData),
                  let rateLimits = event.rateLimits else {
                continue
            }

            return rateLimits
        }

        return nil
    }

    private func isCodexInPath() -> Bool {
        let commonPaths = [
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
            "/opt/homebrew/bin/codex"
        ]
        return commonPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func mapToSnapshot(_ limits: CodexRateLimits) -> ProviderUsageSnapshot {
        let shortWindow = WindowUsage(
            label: "5-Hour Window",
            utilization: limits.primary.usedPercent,
            resetsAt: Date(timeIntervalSince1970: limits.primary.resetsAt),
            windowDuration: Double(limits.primary.windowMinutes) * 60
        )

        let longWindow = WindowUsage(
            label: "7-Day Window",
            utilization: limits.secondary.usedPercent,
            resetsAt: Date(timeIntervalSince1970: limits.secondary.resetsAt),
            windowDuration: Double(limits.secondary.windowMinutes) * 60
        )

        let plan = inferPlan(from: limits.credits)

        return ProviderUsageSnapshot(
            shortWindow: shortWindow,
            longWindow: longWindow,
            planLabel: plan,
            extraUsage: nil,
            creditsBalance: limits.credits?.balance
        )
    }

    private func inferPlan(from credits: CodexCredits?) -> String {
        guard let credits else { return "Free" }
        if credits.unlimited { return "Pro" }
        if credits.hasCredits { return "Plus" }
        return "Free"
    }
}

// MARK: - Codex Data Models

private enum CodexError: Error {
    case noSessionData
}

private struct CodexAuth: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

/// A single line in a Codex session JSONL file
private struct CodexSessionEvent: Decodable {
    let rateLimits: CodexRateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

struct CodexRateLimits: Decodable, Sendable {
    let primary: CodexRateLimitWindow
    let secondary: CodexRateLimitWindow
    let credits: CodexCredits?
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
