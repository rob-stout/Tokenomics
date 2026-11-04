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
/// Admin elevation (Homebrew's own installer script) is handled via NSAppleScript
/// `do shell script … with administrator privileges`, which triggers macOS's
/// native authentication dialog without opening a Terminal window.
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

        // Detached so stderr drains while this actor blocks reading stdout below.
        // An actor-inherited Task couldn't start until the actor suspends, so a
        // chatty install that filled the ~64KB stderr pipe would deadlock.
        let stderrTask = Task.detached { () -> [String] in
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines { continuation.yield(.log("[npm stderr] \(line)")) }
            return lines
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: stdoutData, encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                continuation.yield(.log(line))
            }
        }

        process.waitUntilExit()
        let stderrLines = await stderrTask.value
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
        let args = ["install"] + (isCask ? ["--cask"] : []) + [formula]

        return AsyncStream<InstallEvent> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task {
                do {
                    try await self.runBrewInstall(
                        brewPath: brewPath,
                        args: args,
                        formula: formula,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    private func runBrewInstall(
        brewPath: URL,
        args: [String],
        formula: String,
        continuation: AsyncStream<InstallEvent>.Continuation
    ) async throws {
        let process = Process()
        self.runningProcess = process

        process.executableURL = brewPath
        process.arguments = args
        process.environment = buildEnvironment(extra: nil)
        process.standardInput = Pipe()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        continuation.yield(.progress(nil))

        try process.run()
        Self.log.info("[GuidedInstallRunner] brew install \(formula) started (pid=\(process.processIdentifier))")

        // Detached so stderr drains while this actor blocks reading stdout below.
        // An actor-inherited Task couldn't start until the actor suspends, so a
        // chatty install that filled the ~64KB stderr pipe would deadlock.
        let stderrTask = Task.detached { () -> [String] in
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines { continuation.yield(.log("[brew stderr] \(line)")) }
            return lines
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: stdoutData, encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                continuation.yield(.log(line))
            }
        }

        process.waitUntilExit()
        let stderrLines = await stderrTask.value
        self.runningProcess = nil

        let exitCode = process.terminationStatus
        if exitCode == 0 {
            Self.log.info("[GuidedInstallRunner] brew install \(formula) succeeded")
            continuation.yield(.completed)
        } else {
            let lastStderr = stderrLines.last ?? "brew exited with code \(exitCode)"
            Self.log.error("[GuidedInstallRunner] brew install \(formula) failed (exit=\(exitCode)): \(lastStderr)")
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

    /// Installs Homebrew via its official installer script with admin elevation.
    ///
    /// The Homebrew installer script requires admin privileges on Intel Macs
    /// (installs to `/usr/local/`) and may prompt on Apple Silicon too.
    /// We use `NSAppleScript` with `do shell script … with administrator privileges`
    /// so macOS shows its native auth dialog — no Terminal window opens.
    ///
    /// **Why we write the shell command to a temp file instead of interpolating
    /// it into the AppleScript source:** AppleScript string literals require any
    /// embedded `"` or `\` to be escaped, and a single missed character produces
    /// the macOS parser error "A unknown token can't go after this ...". By
    /// passing only a generated temp-file path to AppleScript, the AppleScript
    /// source is structurally static and cannot trigger that class of parser
    /// error. The path is constructed from UUID + a fixed prefix inside
    /// `FileManager.default.temporaryDirectory`, so it contains only safe ASCII.
    ///
    /// The user can cancel the dialog; if they do, the stream emits `.failed`.
    ///
    /// - Returns: An `AsyncStream<InstallEvent>` terminating with `.completed` or `.failed`.
    func installHomebrew() async throws -> AsyncStream<InstallEvent> {
        let installerURL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

        // Generated path — safe ASCII by construction. No AppleScript escaping needed.
        let tempScript = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenomics-brew-install-\(UUID().uuidString).sh")
        let scriptBody = """
        #!/bin/bash
        /bin/bash -c "$(curl -fsSL \(installerURL))"
        """

        return AsyncStream<InstallEvent> { continuation in
            // AppleScript execution is synchronous — run it off the main thread.
            Task {
                continuation.yield(.progress(nil))
                Self.log.info("[GuidedInstallRunner] Starting Homebrew installer via AppleScript admin elevation")

                // Write + chmod the temp installer script. Fail early if we can't.
                do {
                    try scriptBody.write(to: tempScript, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: tempScript.path
                    )
                } catch {
                    continuation.yield(.failed("Could not prepare Homebrew installer: \(error.localizedDescription)"))
                    continuation.finish()
                    return
                }

                // Best-effort cleanup — the temp script has run by the time we get here.
                defer { try? FileManager.default.removeItem(at: tempScript) }

                let appleScriptSource = "do shell script \"\(tempScript.path)\" with administrator privileges"

                var appleScriptError: NSDictionary?
                guard let script = NSAppleScript(source: appleScriptSource) else {
                    continuation.yield(.failed("Could not create AppleScript for Homebrew install."))
                    continuation.finish()
                    return
                }

                // executeAndReturnError is blocking — this Task runs on a cooperative thread,
                // which is fine because it just waits on the subprocess.
                _ = script.executeAndReturnError(&appleScriptError)

                if let error = appleScriptError {
                    let message = error[NSAppleScript.errorMessage] as? String
                        ?? "Homebrew installation failed or was cancelled."
                    Self.log.error("[GuidedInstallRunner] Homebrew install via AppleScript failed: \(message)")
                    continuation.yield(.failed(message))
                } else {
                    Self.log.info("[GuidedInstallRunner] Homebrew installer completed successfully")
                    continuation.yield(.completed)
                }
                continuation.finish()
            }
        }
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

        // Detached (and streamLines nonisolated) so both pipes drain while this
        // actor blocks in waitUntilExit() — otherwise a full pipe deadlocks.
        let stdoutTask = Task.detached {
            await self.streamLines(from: stdoutPipe.fileHandleForReading) { line in
                continuation.yield(.stdout(line))
                if let event = CLIOutputParser.parseDeviceCode(from: line) {
                    continuation.yield(event)
                }
            }
        }

        let stderrTask = Task.detached {
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

    nonisolated private func streamLines(
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
