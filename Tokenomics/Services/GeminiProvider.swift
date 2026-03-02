import Foundation

/// Gemini CLI usage provider — detects installation and auth, but usage tracking is not yet available
actor GeminiProvider: UsageProvider {
    let id = ProviderId.gemini

    private let authFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.authFile = home.appendingPathComponent(".gemini/oauth_creds.json")
    }

    func checkConnection() async -> ProviderConnectionState {
        guard isGeminiInstalled() else {
            return .notInstalled
        }

        // Check for OAuth credentials file
        guard FileManager.default.fileExists(atPath: authFile.path) else {
            return .installedNoAuth
        }

        // Verify the creds file has content (not empty/corrupt)
        guard let data = try? Data(contentsOf: authFile),
              !data.isEmpty else {
            return .installedNoAuth
        }

        return .connected(plan: "—")
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        // Gemini CLI doesn't expose rate-limit data yet
        throw AppError.unexpectedError(underlying: GeminiError.usageNotSupported)
    }

    // MARK: - Private

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

private enum GeminiError: LocalizedError {
    case usageNotSupported

    var errorDescription: String? {
        "Gemini CLI does not expose usage data yet."
    }
}
