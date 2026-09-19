import Foundation

// MARK: - SystemPrerequisiteDetector

/// Synchronous, subprocess-free detection of system prerequisites.
///
/// All checks are pure filesystem existence + executable-bit tests.
/// No shell commands are invoked. Safe to call from any thread/actor.
///
/// Returns a `URL` to the first found binary, or `nil` if not detected.
/// The returned `URL` is always a `file://` URL to the resolved path.
enum SystemPrerequisiteDetector {

    // MARK: - Homebrew

    /// Returns the path to `brew` if Homebrew is installed, otherwise `nil`.
    ///
    /// Checks the standard locations in install-frequency order:
    /// - `/opt/homebrew/bin/brew` — Apple Silicon default
    /// - `/usr/local/bin/brew`    — Intel default
    static func homebrewPath() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        return firstExecutable(among: candidates)
    }

    // MARK: - Node / npm

    /// Returns the path to `node` if available, otherwise `nil`.
    ///
    /// Checks Homebrew locations first, then common version-manager conventions:
    /// nvm (`~/.nvm/versions/node/*/bin/node`),
    /// fnm (`~/.fnm/aliases/default/bin/node`),
    /// Volta (`~/.volta/bin/node`).
    static func nodePath() -> URL? {
        // Static Homebrew paths first — fastest check.
        let staticCandidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
        ]
        if let found = firstExecutable(among: staticCandidates) {
            return found
        }

        // Version-manager paths require filesystem enumeration.
        return firstExecutable(among: versionManagerPaths(binary: "node"))
    }

    /// Returns the path to `npm` if available, otherwise `nil`.
    ///
    /// npm ships with Node.js, so the search mirrors `nodePath()`.
    static func npmPath() -> URL? {
        let staticCandidates = [
            "/opt/homebrew/bin/npm",
            "/usr/local/bin/npm",
        ]
        if let found = firstExecutable(among: staticCandidates) {
            return found
        }

        return firstExecutable(among: versionManagerPaths(binary: "npm"))
    }

    // MARK: - gh CLI

    /// Returns the path to the `gh` CLI if installed via Homebrew, otherwise `nil`.
    ///
    /// `gh` is distributed as a compiled binary via Homebrew only — no version-manager
    /// variants to check.
    static func ghPath() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
        ]
        return firstExecutable(among: candidates)
    }

    // MARK: - Claude Code

    /// Returns the path to the `claude` binary if Claude Code is installed, otherwise `nil`.
    ///
    /// Single source of truth for Claude Code detection — `ClaudeConnector`,
    /// `ClaudeProvider`, and the connector's detect checklist all call this.
    ///
    /// Checks, in order:
    /// - `~/.local/bin/claude`      — Anthropic's native installer (what Tokenomics uses)
    /// - `/opt/homebrew/bin/claude` — Homebrew cask, Apple Silicon
    /// - `/usr/local/bin/claude`    — Homebrew cask on Intel, or a global npm install
    /// - `~/.claude/local/claude`, `~/.claude/bin/claude` — older Anthropic local installs
    /// - nvm / fnm / Volta bins     — `npm install -g @anthropic-ai/claude-code`
    static func claudePath() -> URL? {
        let home = NSHomeDirectory()
        let staticCandidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.claude/bin/claude",
        ]
        if let found = firstExecutable(among: staticCandidates) {
            return found
        }

        return firstExecutable(among: versionManagerPaths(binary: "claude"))
    }

    // MARK: - Tokenomics per-user npm bin

    /// Returns the path to a binary installed in Tokenomics' per-user npm prefix,
    /// or `nil` if it hasn't been installed yet.
    ///
    /// Binaries land in `~/.tokenomics-cli/bin/<binary>` after
    /// `GuidedInstallRunner.installNpmPackage` completes.
    ///
    /// - Parameter binary: The binary name to look for (e.g. `"codex"`, `"gemini"`).
    static func tokenomicsNpmBinPath(_ binary: String) -> URL? {
        let binDir = GuidedInstallRunner.npmBinDir
        let candidate = binDir.appendingPathComponent(binary)
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    // MARK: - Private helpers

    /// Returns the first path in `candidates` that is an executable file.
    private static func firstExecutable(among candidates: [String]) -> URL? {
        let fm = FileManager.default
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Resolves `binary` under version-manager directories that use glob-like
    /// structures (nvm, fnm, Volta). Uses `FileManager` enumeration — no shell.
    ///
    /// Version managers supported:
    /// - **nvm**: `~/.nvm/versions/node/` contains one directory per installed
    ///   version (e.g. `v22.0.0`). We enumerate and take the first that has the
    ///   binary. (The active version would normally be on PATH, but here we just
    ///   want to confirm Node is available somewhere.)
    /// - **fnm**: `~/.fnm/aliases/default/bin/` points to the default version.
    /// - **Volta**: `~/.volta/bin/` is a flat bin directory.
    private static func versionManagerPaths(binary: String) -> [String] {
        let home = NSHomeDirectory()
        var paths: [String] = []

        // nvm: enumerate ~/.nvm/versions/node/*/bin/<binary>
        let nvmVersionsDir = URL(fileURLWithPath: "\(home)/.nvm/versions/node")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: nvmVersionsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) {
            for entry in entries {
                paths.append(entry.appendingPathComponent("bin/\(binary)").path)
            }
        }

        // fnm: ~/.fnm/aliases/default/bin/<binary>
        paths.append("\(home)/.fnm/aliases/default/bin/\(binary)")

        // Volta: ~/.volta/bin/<binary>
        paths.append("\(home)/.volta/bin/\(binary)")

        return paths
    }
}
