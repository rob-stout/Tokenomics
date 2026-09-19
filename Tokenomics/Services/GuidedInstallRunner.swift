import Foundation
import os

// MARK: - Errors

enum GuidedInstallError: Error, LocalizedError {
    case executableNotFound(URL)
    case processFailed(exitCode: Int32, stderr: String)
    case adminElevationFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let url):
            return "Executable not found at \(url.path)."
        case .processFailed(let code, let stderr):
            return "Process exited with code \(code). \(stderr)"
        case .adminElevationFailed(let reason):
            return "Admin elevation failed: \(reason)"
        case .cancelled:
            return "Operation cancelled."
        }
    }
}

// MARK: - GuidedInstallRunner

/// Actor wrapping `Process` for running system commands as hidden subprocesses.
///
/// Works with any system binary — brew, npm, node, gh. Callers supply the
/// full path to the executable so there is no PATH-lookup ambiguity.
///
/// npm installs are routed to a per-user prefix (`~/.tokenomics-cli/`) so they
/// never need elevated permissions, regardless of where Homebrew is installed.
///
/// Homebrew itself is the exception: its installer needs the user's password on
/// a real TTY, so it runs in a Terminal window Tokenomics opens (see `installHomebrew()`).
actor GuidedInstallRunner {

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "GuidedInstallRunner")

    // MARK: - Per-user npm prefix

    /// Root of Tokenomics-managed npm installs for system Node.
    ///
    /// Using a home-directory path (not Application Support) so the binaries
    /// land somewhere the system shell PATH can easily be extended to include.
    private static var tokenomicsNpmPrefix: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".tokenomics-cli")
    }

    /// The `bin/` directory inside our per-user npm prefix.
    /// Binaries installed via `installNpmPackage` land here.
    static var npmBinDir: URL {
        tokenomicsNpmPrefix.appendingPathComponent("bin")
    }

    // MARK: - In-flight process tracking

    /// The currently-running process, if any. Stored so `cancel()` can terminate it.
    private var runningProcess: Process?

    // MARK: - Cancel

    /// Terminates the running process, if any. Safe to call multiple times.
    func cancel() {
        terminalWaitTask?.cancel()
        terminalWaitTask = nil
        guard let process = runningProcess, process.isRunning else { return }
        Self.log.info("[GuidedInstallRunner] Cancelling process \(process.processIdentifier)")
        process.terminate()
        runningProcess = nil
    }

    // MARK: - Generic command runner

    /// Runs a system binary and streams its output as typed `RunEvent`s.
    ///
    /// Parses stdout/stderr for OAuth device-code URLs and emits
    /// `.deviceCode(url:code:)` events when found, matching the pattern
    /// established by the legacy embedded-CLI runner.
    ///
    /// - Parameters:
    ///   - executable: Full path to the binary (e.g. `/opt/homebrew/bin/gh`).
    ///   - args: Arguments to pass.
    ///   - extraEnv: Additional environment variables merged on top of the
    ///     base environment. Useful for injecting `npm_config_prefix` etc.
    /// - Returns: A `RunCLIHandle` with the event stream and a stdin writer.
    func runCommand(
        executable: URL,
        args: [String],
        extraEnv: [String: String]? = nil
    ) async throws -> RunCLIHandle {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw GuidedInstallError.executableNotFound(executable)
        }

        let stdinPipe = Pipe()
        let stdinHandle = stdinPipe.fileHandleForWriting

        let stream = AsyncStream<RunEvent> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task {
                do {
                    try await self.runProcess(
                        executable: executable,
                        args: args,
                        extraEnv: extraEnv,
                        stdinPipe: stdinPipe,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.stderr(error.localizedDescription))
                    continuation.yield(.exited(-1))
                    continuation.finish()
                }
            }
        }

        return RunCLIHandle(
            events: stream,
            writeStdin: { input in
                guard let data = input.data(using: .utf8) else { return }
                // try? swallows "broken pipe" if the process exited before write —
                // that's a benign race condition, not a failure.
                try? stdinHandle.write(contentsOf: data)
            }
        )
    }

    // MARK: - npm install

    /// Installs an npm package using the system npm binary with a per-user prefix.
    ///
    /// The per-user prefix (`~/.tokenomics-cli/`) means the install never
    /// requires sudo, even when Homebrew's Node lands in `/opt/homebrew/`.
    ///
    /// - Parameters:
    ///   - npmPath: Full path to the `npm` binary (from `SystemPrerequisiteDetector.npmPath()`).
    ///   - package: The npm package name, e.g. `"@openai/codex"`.
    /// - Returns: An `AsyncStream<InstallEvent>` terminating with `.completed` or `.failed`.
    func installNpmPackage(
        npmPath: URL,
        package: String
    ) async throws -> AsyncStream<InstallEvent> {
        try createDirectoryIfNeeded(at: Self.tokenomicsNpmPrefix)

        let prefixPath = Self.tokenomicsNpmPrefix.path
        let cachePath = Self.tokenomicsNpmPrefix.appendingPathComponent(".npm-cache").path

        let extraEnv: [String: String] = [
            "npm_config_prefix": prefixPath,
            "npm_config_cache": cachePath,
        ]

        return AsyncStream<InstallEvent> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task {
                do {
                    try await self.runNpmInstall(
                        npmPath: npmPath,
                        package: package,
                        extraEnv: extraEnv,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    private func runNpmInstall(
        npmPath: URL,
        package: String,
        extraEnv: [String: String],
        continuation: AsyncStream<InstallEvent>.Continuation
    ) async throws {
        let process = Process()
        self.runningProcess = process

        process.executableURL = npmPath
        process.arguments = [
            "install",
            "--global",
            "--no-fund",
            "--no-audit",
            package
        ]
        process.environment = buildEnvironment(extra: extraEnv)
        process.standardInput = Pipe()  // stdin closed — npm should not prompt

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        continuation.yield(.progress(nil))   // indeterminate — npm has no machine-readable progress

        try process.run()
        Self.log.info("[GuidedInstallRunner] npm install \(package) started (pid=\(process.processIdentifier))")

        var stderrLines: [String] = []
        let stderrTask = Task {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8) {
                stderrLines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                for line in stderrLines {
                    continuation.yield(.log("[npm stderr] \(line)"))
                }
            }
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: stdoutData, encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                continuation.yield(.log(line))
            }
        }

        process.waitUntilExit()
        _ = await stderrTask.result
        self.runningProcess = nil

        let exitCode = process.terminationStatus
        if exitCode == 0 {
            Self.log.info("[GuidedInstallRunner] npm install \(package) succeeded")
            continuation.yield(.completed)
        } else {
            let lastStderr = stderrLines.last ?? "npm exited with code \(exitCode)"
            Self.log.error("[GuidedInstallRunner] npm install \(package) failed (exit=\(exitCode)): \(lastStderr)")
            // Surface EACCES as a typed failure token so connectors can classify it.
            if let eacces = extractEACCESPath(from: stderrLines) {
                continuation.yield(.failed("EACCES:\(eacces)"))
            } else {
                continuation.yield(.failed(lastStderr))
            }
        }
        continuation.finish()
    }

    // MARK: - Homebrew formula/cask install

    /// Installs a Homebrew formula or cask and streams progress.
    ///
    /// Runs `brew install [--cask] <formula>` as a hidden subprocess.
    /// Does NOT require admin privileges on Apple Silicon (Homebrew installs
    /// to `/opt/homebrew/` which is user-writable after the Homebrew setup).
    ///
    /// - Parameters:
    ///   - brewPath: Full path to the `brew` binary.
    ///   - formula: Formula or cask name (e.g. `"node"`, `"gh"`).
    ///   - isCask: Pass `true` for cask installs (`brew install --cask`).
    /// - Returns: An `AsyncStream<InstallEvent>` terminating with `.completed` or `.failed`.
    func installViaHomebrew(
        brewPath: URL,
        formula: String,
        isCask: Bool = false
    ) async throws -> AsyncStream<InstallEvent> {
        var args = ["install"]
        if isCask { args.append("--cask") }
        args.append(formula)

        return AsyncStream<InstallEvent> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task {
                do {
                    try await self.runInstallProcess(
                        executable: brewPath,
                        args: args,
                        label: "brew install \(formula)",
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Claude Code native installer

    /// Installs Claude Code with Anthropic's native installer
    /// (`curl -fsSL https://claude.ai/install.sh | bash`).
    ///
    /// Runs as the current user — the installer writes only under `$HOME`
    /// (binary symlinked at `~/.local/bin/claude`) and refuses to run under
    /// sudo, so no admin elevation or Homebrew is involved. Verified to run
    /// cleanly without a TTY.
    ///
    /// `pipefail` matters: without it a failed `curl` pipes nothing into
    /// `bash`, which then exits 0 and the install looks successful.
    ///
    /// - Returns: An `AsyncStream<InstallEvent>` terminating with `.completed` or `.failed`.
    func installClaudeCodeNative() async throws -> AsyncStream<InstallEvent> {
        AsyncStream<InstallEvent> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task {
                do {
                    try await self.runInstallProcess(
                        executable: URL(fileURLWithPath: "/bin/bash"),
                        args: ["-c", "set -o pipefail; curl -fsSL https://claude.ai/install.sh | bash"],
                        label: "Claude Code native install",
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    /// Runs an install command as a hidden subprocess and maps its exit to
    /// `.completed` / `.failed`. Shared by brew and the Claude native installer.
    private func runInstallProcess(
        executable: URL,
        args: [String],
        label: String,
        continuation: AsyncStream<InstallEvent>.Continuation
    ) async throws {
        let process = Process()
        self.runningProcess = process

        process.executableURL = executable
        process.arguments = args
        process.environment = buildEnvironment(extra: nil)
        process.standardInput = Pipe()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        continuation.yield(.progress(nil))

        try process.run()
        Self.log.info("[GuidedInstallRunner] \(label) started (pid=\(process.processIdentifier))")

        var stderrLines: [String] = []
        let stderrTask = Task {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8) {
                stderrLines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                for line in stderrLines { continuation.yield(.log("[stderr] \(line)")) }
            }
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: stdoutData, encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                continuation.yield(.log(line))
            }
        }

        process.waitUntilExit()
        _ = await stderrTask.result
        self.runningProcess = nil

        let exitCode = process.terminationStatus
        if exitCode == 0 {
            Self.log.info("[GuidedInstallRunner] \(label) succeeded")
            continuation.yield(.completed)
        } else {
            let lastStderr = stderrLines.last ?? "\(label) exited with code \(exitCode)"
            Self.log.error("[GuidedInstallRunner] \(label) failed (exit=\(exitCode)): \(lastStderr)")
            // Surface EACCES as a typed failure token so connectors can classify it.
            if let eacces = extractEACCESPath(from: stderrLines) {
                continuation.yield(.failed("EACCES:\(eacces)"))
            } else {
                continuation.yield(.failed(lastStderr))
            }
        }
        continuation.finish()
    }

    // MARK: - Homebrew itself

    /// `.failed` reason emitted when macOS blocks Tokenomics from controlling
    /// Terminal (Automation permission). Connectors map it to
    /// `ConnectorError.automationPermissionDenied`.
    static let automationDeniedReason = "TERMINAL_AUTOMATION_DENIED"

    /// How long to wait for the Terminal-based Homebrew install before giving up.
    /// Generous because a fresh Mac also downloads Apple's Command Line Tools
    /// (often 5–15 minutes). `ConnectorViewModel`'s stuck threshold for
    /// `.installingInTerminal` sits above this so the runner's message wins.
    static let homebrewTimeout: TimeInterval = 25 * 60

    /// Polling task for the Terminal-based Homebrew install, kept so `cancel()` can stop it.
    private var terminalWaitTask: Task<Void, Never>?

    /// Installs Homebrew by opening Terminal with its official installer, then
    /// waits for the install to finish.
    ///
    /// **Why Terminal and not a hidden process:** Homebrew's installer must run
    /// as the logged-in user — it aborts as root ("Don't run this as root!") —
    /// but it needs `sudo` partway through, which prompts for the password on a
    /// TTY. An AppleScript `with administrator privileges` runs it as root, so it
    /// can never succeed; a hidden `Process` has no TTY for the password. Terminal
    /// gives it both. It also installs Apple's Command Line Tools when missing.
    /// (Homebrew's `.pkg` was ruled out: Apple Silicon + macOS 15+ only, and it
    /// hard-fails without Command Line Tools already installed.)
    ///
    /// **Completion signal:** the Terminal command touches a success or failure
    /// marker file when the installer exits. We watch for those rather than for
    /// `brew` itself, because `bin/brew` appears mid-install — moving on then
    /// would race the installer's own `brew update`.
    ///
    /// - Returns: A stream that emits `.progress(nil)`, then `.completed`, or
    ///   `.failed` (installer error, timeout, or `automationDeniedReason`).
    func installHomebrew() async throws -> AsyncStream<InstallEvent> {
        let (stream, continuation) = AsyncStream<InstallEvent>.makeStream()

        let markerBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenomics-brew-\(UUID().uuidString)")
        let okMarker = markerBase.appendingPathExtension("ok")
        let failMarker = markerBase.appendingPathExtension("failed")
        let installer = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
        let command = "\(installer) && { touch \(Self.shellQuoted(okMarker.path)); echo; "
            + "echo 'Homebrew is installed. You can close this window and go back to Tokenomics.'; } "
            + "|| touch \(Self.shellQuoted(failMarker.path))"

        terminalWaitTask?.cancel()
        let task = Task {
            continuation.yield(.progress(nil))
            Self.log.info("[GuidedInstallRunner] Opening Terminal for Homebrew install")

            switch await Self.openInTerminal(command) {
            case .opened:
                break
            case .automationDenied:
                continuation.yield(.failed(Self.automationDeniedReason))
                continuation.finish()
                return
            case .failed(let message):
                continuation.yield(.failed(message))
                continuation.finish()
                return
            }

            let fm = FileManager.default
            let deadline = Date().addingTimeInterval(Self.homebrewTimeout)
            defer {
                try? fm.removeItem(at: okMarker)
                try? fm.removeItem(at: failMarker)
            }
            while !Task.isCancelled {
                if fm.fileExists(atPath: okMarker.path), SystemPrerequisiteDetector.homebrewPath() != nil {
                    Self.log.info("[GuidedInstallRunner] Homebrew installer finished successfully")
                    continuation.yield(.completed)
                    break
                }
                if fm.fileExists(atPath: failMarker.path) {
                    Self.log.error("[GuidedInstallRunner] Homebrew installer exited with an error")
                    continuation.yield(.failed("Homebrew's installer stopped before finishing. Check the Terminal window for details, then try again."))
                    break
                }
                if Date() > deadline {
                    Self.log.error("[GuidedInstallRunner] Timed out waiting for Homebrew install")
                    continuation.yield(.failed("Homebrew didn't finish installing. If Terminal is still working, let it finish, then try again."))
                    break
                }
                try? await Task.sleep(for: .seconds(2))
            }
            continuation.finish()
        }
        terminalWaitTask = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: - Terminal

    enum TerminalLaunchResult: Sendable {
        case opened
        /// macOS Automation (TCC) denied Tokenomics control of Terminal.
        case automationDenied
        case failed(String)
    }

    /// Opens a new Terminal window running `command` and brings Terminal forward.
    ///
    /// The first call triggers macOS's Automation permission prompt ("Tokenomics
    /// wants to control Terminal"). AppleScript blocks while that's up, so this
    /// runs on a global queue rather than tying up an actor.
    static func openInTerminal(_ command: String) async -> TerminalLaunchResult {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            do script "\(escaped)"
            activate
        end tell
        """
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&error)
                guard let error else {
                    continuation.resume(returning: .opened)
                    return
                }
                Self.log.error("[GuidedInstallRunner] Terminal launch error: \(error)")
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                let message = error[NSAppleScript.errorMessage] as? String ?? ""
                let lower = message.lowercased()
                if code == -1743 || lower.contains("not authorized") || lower.contains("automation") {
                    continuation.resume(returning: .automationDenied)
                } else {
                    continuation.resume(returning: .failed(message.isEmpty ? "Couldn't open Terminal." : message))
                }
            }
        }
    }

    /// Single-quotes a string for the shell (safe with spaces and quotes).
    static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Private process runner

    private func runProcess(
        executable: URL,
        args: [String],
        extraEnv: [String: String]?,
        stdinPipe: Pipe,
        continuation: AsyncStream<RunEvent>.Continuation
    ) async throws {
        let process = Process()
        self.runningProcess = process

        process.executableURL = executable
        process.arguments = args
        process.environment = buildEnvironment(extra: extraEnv)
        process.standardInput = stdinPipe

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        Self.log.info("[GuidedInstallRunner] \(executable.lastPathComponent) \(args.joined(separator: " ")) (pid=\(process.processIdentifier))")

        let stdoutTask = Task {
            await self.streamLines(from: stdoutPipe.fileHandleForReading) { line in
                continuation.yield(.stdout(line))
                if let event = CLIOutputParser.parseDeviceCode(from: line) {
                    continuation.yield(event)
                }
            }
        }

        let stderrTask = Task {
            await self.streamLines(from: stderrPipe.fileHandleForReading) { line in
                continuation.yield(.stderr(line))
                if let event = CLIOutputParser.parseDeviceCode(from: line) {
                    continuation.yield(event)
                }
            }
        }

        process.waitUntilExit()
        _ = await stdoutTask.result
        _ = await stderrTask.result
        self.runningProcess = nil

        let exitCode = process.terminationStatus
        Self.log.info("[GuidedInstallRunner] \(executable.lastPathComponent) exited with code \(exitCode)")
        continuation.yield(.exited(exitCode))
        continuation.finish()
    }

    // MARK: - Environment helpers

    /// Builds the base subprocess environment, optionally merging caller-supplied extras.
    ///
    /// Key variables:
    /// - PATH: inherits current PATH, prepending our per-user bin dir so that
    ///   binaries we installed are immediately visible without re-sourcing.
    /// - HOME: inherits the actual user home so CLIs write auth files to the right place.
    /// - TERM/CI: suppress interactive color/progress output.
    private func buildEnvironment(extra: [String: String]?) -> [String: String] {
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        let ourBinPath = GuidedInstallRunner.npmBinDir.path

        var env: [String: String] = [
            "PATH": "\(ourBinPath):\(currentPath)",
            "HOME": NSHomeDirectory(),
            "TERM": "dumb",
            "CI": "true",
        ]

        if let lang = ProcessInfo.processInfo.environment["LANG"] {
            env["LANG"] = lang
        }

        if let extra {
            for (key, value) in extra {
                env[key] = value
            }
        }

        return env
    }

    // MARK: - Line streaming

    private func streamLines(
        from handle: FileHandle,
        handler: @Sendable (String) -> Void
    ) async {
        let data = handle.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                handler(line)
            }
        }
    }

    // MARK: - EACCES classification helper

    /// Scans stderr lines for EACCES or "Permission denied" and returns the
    /// offending path if found. Returns nil if no permission error is present.
    ///
    /// npm formats it as: `EACCES: permission denied, mkdir '/some/path'`
    /// brew formats it as: `Permission denied @ rb_file_s_mkdir - /some/path`
    private func extractEACCESPath(from lines: [String]) -> String? {
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("eacces") || lower.contains("permission denied") else { continue }

            // npm pattern: EACCES: permission denied, <action> '<path>'
            if let range = line.range(of: "'([^']+)'", options: .regularExpression) {
                let match = String(line[range]).trimmingCharacters(in: .init(charactersIn: "'"))
                return match
            }
            // brew pattern: Permission denied @ rb_file_s_mkdir - /path
            // The " - /" sequence precedes the path; slice from the "/" onward.
            if let dashRange = line.range(of: " - /") {
                let pathStart = line.index(dashRange.upperBound, offsetBy: -1)
                let path = String(line[pathStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return path
            }
            // Fallback — return the whole line truncated
            return String(line.prefix(80))
        }
        return nil
    }

    /// Removes the Tokenomics npm cache directory so a subsequent npm install
    /// starts clean. Called as the recovery action for `.permissionDenied`.
    func clearNpmCache() async {
        let cacheDir = Self.tokenomicsNpmPrefix.appendingPathComponent(".npm-cache")
        do {
            if FileManager.default.fileExists(atPath: cacheDir.path) {
                try FileManager.default.removeItem(at: cacheDir)
                Self.log.info("[GuidedInstallRunner] Cleared npm cache at \(cacheDir.path)")
            }
        } catch {
            Self.log.error("[GuidedInstallRunner] Failed to clear npm cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Directory helpers

    private func createDirectoryIfNeeded(at url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
