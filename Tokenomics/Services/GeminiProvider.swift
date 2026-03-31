import Foundation
import os

/// Gemini CLI usage provider — counts requests from local session files against plan limits
actor GeminiProvider: UsageProvider {
    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "GeminiProvider")
    let id = ProviderId.gemini
    let pollInterval: TimeInterval = 60 // 1 min — local files, no rate limit

    private let authFile: URL
    private let tmpDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.authFile = home.appendingPathComponent(".gemini/oauth_creds.json")
        self.tmpDir = home.appendingPathComponent(".gemini/tmp")
    }

    func checkConnection() async -> ProviderConnectionState {
        guard isGeminiInstalled() else {
            return .notInstalled
        }

        guard FileManager.default.fileExists(atPath: authFile.path) else {
            return .installedNoAuth
        }

        guard let data = try? Data(contentsOf: authFile),
              !data.isEmpty else {
            return .installedNoAuth
        }

        let plan = SettingsService.geminiPlan ?? .free
        return .connected(plan: plan.displayLabel)
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let plan = SettingsService.geminiPlan ?? .free
        let now = Date()

        let messages = collectGeminiMessages()
        let midnightPT = Self.midnightPacific(for: now)

        var dailyCount = 0
        var dailyTokens = 0

        for message in messages {
            if message.timestamp >= midnightPT {
                dailyCount += 1
                dailyTokens += message.totalTokens
            }
        }

        let requestUtilization = Double(dailyCount) / Double(plan.dailyLimit) * 100
        let tokenUtilization = Double(dailyTokens) / Double(plan.dailyTokenBudget) * 100

        let nextMidnightPT = midnightPT.addingTimeInterval(86400)

        let requestSublabel = "\(dailyCount) of \(plan.dailyLimit.formatted()) requests today"
        let tokenSublabel = "\(Self.formatTokens(dailyTokens)) of \(Self.formatTokens(plan.dailyTokenBudget)) tokens today"

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Tokens Today",
                utilization: min(tokenUtilization, 100),
                resetsAt: nextMidnightPT,
                windowDuration: 86400,
                sublabelOverride: tokenSublabel
            ),
            longWindow: WindowUsage(
                label: "Requests Today",
                utilization: min(requestUtilization, 100),
                resetsAt: nextMidnightPT,
                windowDuration: 86400,
                sublabelOverride: requestSublabel
            ),
            planLabel: plan.displayLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    /// Formats token counts for display (e.g. 20,481 → "20.5K")
    private static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Date Parsing

    /// Gemini timestamps include milliseconds (e.g. "2026-03-03T16:02:55.528Z")
    /// which the default .iso8601 strategy doesn't handle
    private static let geminiDateStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
    }

    // MARK: - Session File Parsing

    /// Collects all `type: "gemini"` messages from today's session files
    private func collectGeminiMessages() -> [GeminiMessage] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: tmpDir.path) else { return [] }

        var results: [GeminiMessage] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = Self.geminiDateStrategy

        // Walk ~/.gemini/tmp/*/chats/session-*.json
        let projectDirs: [String]
        do {
            projectDirs = try fm.contentsOfDirectory(atPath: tmpDir.path)
        } catch {
            Self.log.error("Failed to list Gemini tmp dir: \(error.localizedDescription)")
            return []
        }

        for project in projectDirs {
            let chatsDir = tmpDir.appendingPathComponent(project).appendingPathComponent("chats")
            let sessionFiles: [String]
            do {
                sessionFiles = try fm.contentsOfDirectory(atPath: chatsDir.path)
            } catch {
                Self.log.debug("Skipping \(project): \(error.localizedDescription)")
                continue
            }

            for file in sessionFiles {
                guard file.hasPrefix("session-") && file.hasSuffix(".json") else { continue }

                let filePath = chatsDir.appendingPathComponent(file)
                do {
                    let data = try Data(contentsOf: filePath)
                    let session = try decoder.decode(GeminiSession.self, from: data)
                    for message in session.messages where message.type == "gemini" {
                        results.append(message)
                    }
                } catch {
                    Self.log.error("Failed to decode \(file): \(error.localizedDescription)")
                    continue
                }
            }
        }

        return results
    }

    // MARK: - Time Helpers

    /// Returns midnight Pacific Time for the given date
    static func midnightPacific(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.startOfDay(for: date)
    }

    // MARK: - Installation Check

    private func isGeminiInstalled() -> Bool {
        let fm = FileManager.default
        let paths = [
            "/opt/homebrew/bin/gemini",
            "/usr/local/bin/gemini",
            "\(NSHomeDirectory())/.local/bin/gemini"
        ]
        return paths.contains { fm.fileExists(atPath: $0) }
    }
}

// MARK: - Gemini Session Models

/// Minimal decode of a Gemini session file — only the fields we need
private struct GeminiSession: Decodable {
    let messages: [GeminiMessage]
}

private struct GeminiMessage: Decodable {
    let type: String
    let timestamp: Date
    let tokens: GeminiTokens?

    var totalTokens: Int { tokens?.total ?? 0 }
}

private struct GeminiTokens: Decodable {
    let input: Int?
    let output: Int?
    let total: Int?
}
