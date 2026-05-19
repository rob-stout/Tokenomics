import Foundation
import AppKit

// MARK: - Detection Signal

/// A single piece of evidence that a brand is present on this Mac.
///
/// Signals are collected independently — a brand can have zero, one, or
/// several signals. The detection actor never infers presence from absence
/// or combines signals from different brands.
enum DetectionSignal: Sendable {
    /// A macOS application with this bundle ID was found in the running app list
    /// or in /Applications.
    case nativeApp(bundleId: String, displayName: String)
    /// A credentials/config directory or file at the given path exists on disk.
    case cliCredentials(path: String, displayName: String)
    /// The NMH bridge wrote ext-side.json recently (within the freshness window).
    case bridgeConnected(lastHeartbeat: Date)
}

// MARK: - Brand Detection Result

/// All signals found for a single brand, plus a pre-rendered annotation string
/// ready for MultiSelectStep to display beneath a brand row.
struct BrandDetection: Sendable {
    let brand: BrandId
    let signals: [DetectionSignal]

    /// Concise annotation shown beneath the brand row in MultiSelectStep.
    ///
    /// Individual signal descriptions are joined with " · ". Empty string when
    /// no signals were found (the brand will not be pre-checked).
    var annotation: String {
        signals.map(\.shortDescription).joined(separator: " · ")
    }

    var isDetected: Bool { !signals.isEmpty }
}

private extension DetectionSignal {
    var shortDescription: String {
        switch self {
        case .nativeApp(_, let displayName):
            return "\(displayName) installed"
        case .cliCredentials(_, let displayName):
            return displayName
        case .bridgeConnected:
            return "browser session active"
        }
    }
}

// MARK: - App Lookup Protocol

/// Abstraction over NSWorkspace so DetectionService can be tested without
/// launching real applications. Production uses `WorkspaceAppLookup`;
/// tests inject a `MockAppLookup`.
protocol AppLookup: Sendable {
    /// Returns true if an application with the given bundle ID is currently
    /// running or installed in standard application directories.
    func isAppPresent(bundleId: String) -> Bool
}

/// Production implementation — delegates to NSWorkspace and FileManager.
struct WorkspaceAppLookup: AppLookup {
    func isAppPresent(bundleId: String) -> Bool {
        // Check running apps first (cheapest check — no disk I/O).
        let running = NSWorkspace.shared.runningApplications
        if running.contains(where: { $0.bundleIdentifier == bundleId }) {
            return true
        }

        // Fall back to asking Launch Services for the bundle URL.
        // This handles installed-but-not-running apps.
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        return url != nil
    }
}

// MARK: - DetectionService

/// Silently detects which AI tools are present on the user's Mac.
///
/// Called once during the Permissions step so results are ready when
/// MultiSelectStep renders. Does not poll — detection is a one-shot read.
///
/// Design constraints:
/// - No network calls — filesystem + subprocess only.
/// - No inferred signals — a signal either fires or it doesn't.
/// - Subprocess use is limited to Copilot's `gh auth status` (required because
///   the gh CLI stores tokens in the system keyring, not a readable file).
actor DetectionService {

    // MARK: - Configuration

    private static let bridgeFreshnessWindow: TimeInterval = 5 * 60 // 5 minutes

    private let appLookup: any AppLookup
    private let fileManager: FileManager
    private let home: String

    // MARK: - Init

    /// - Parameters:
    ///   - appLookup: Injectable for testing. Defaults to the real NSWorkspace lookup.
    ///   - fileManager: Injectable for testing. Defaults to `FileManager.default`.
    init(
        appLookup: any AppLookup = WorkspaceAppLookup(),
        fileManager: FileManager = .default
    ) {
        self.appLookup = appLookup
        self.fileManager = fileManager
        self.home = fileManager.homeDirectoryForCurrentUser.path
    }

    // MARK: - Public API

    /// Runs all brand detections concurrently and returns a map of brand → result.
    ///
    /// Brands with no signals are omitted from the result — callers should treat
    /// a missing key as "not detected" rather than an error.
    func detect() async -> [BrandId: BrandDetection] {
        // Run all brand detections concurrently via a task group.
        return await withTaskGroup(of: BrandDetection?.self) { group in
            group.addTask { await self.detectAnthropic() }
            group.addTask { await self.detectOpenAI() }
            group.addTask { await self.detectGoogle() }
            group.addTask { await self.detectCopilot() }
            group.addTask { await self.detectCursor() }
            // API-key brands (Stability, Midjourney, Runway, ElevenLabs) have no
            // detectable local presence without Keychain access — omitted per spec.

            var result: [BrandId: BrandDetection] = [:]
            for await detection in group {
                guard let detection, detection.isDetected else { continue }
                result[detection.brand] = detection
            }
            return result
        }
    }

    // MARK: - Per-Brand Detectors

    private func detectAnthropic() async -> BrandDetection? {
        var signals: [DetectionSignal] = []

        // Claude desktop app
        if appLookup.isAppPresent(bundleId: "com.anthropic.claudefordesktop") {
            signals.append(.nativeApp(bundleId: "com.anthropic.claudefordesktop", displayName: "Claude.app"))
        }

        // Claude Code CLI — credentials directory created on first sign-in
        let claudeDir = "\(home)/.claude"
        if fileManager.fileExists(atPath: claudeDir) {
            signals.append(.cliCredentials(path: claudeDir, displayName: "Claude Code CLI"))
        }

        // Bridge freshness: claude.ai web session via extension
        if let heartbeat = bridgeHeartbeat(for: .claude) {
            signals.append(.bridgeConnected(lastHeartbeat: heartbeat))
        }

        return BrandDetection(brand: .anthropic, signals: signals)
    }

    private func detectOpenAI() async -> BrandDetection? {
        var signals: [DetectionSignal] = []

        // ChatGPT desktop app
        if appLookup.isAppPresent(bundleId: "com.openai.chat") {
            signals.append(.nativeApp(bundleId: "com.openai.chat", displayName: "ChatGPT.app"))
        }

        // Codex CLI — credentials directory created on first sign-in
        let codexDir = "\(home)/.codex"
        if fileManager.fileExists(atPath: codexDir) {
            signals.append(.cliCredentials(path: codexDir, displayName: "Codex CLI"))
        }

        // Bridge freshness: chatgpt.com web session via extension
        if let heartbeat = bridgeHeartbeat(for: .chatgpt) {
            signals.append(.bridgeConnected(lastHeartbeat: heartbeat))
        }

        return BrandDetection(brand: .openai, signals: signals)
    }

    private func detectGoogle() async -> BrandDetection? {
        var signals: [DetectionSignal] = []

        // Gemini CLI — credentials directory created on first sign-in
        let geminiDir = "\(home)/.gemini"
        if fileManager.fileExists(atPath: geminiDir) {
            signals.append(.cliCredentials(path: geminiDir, displayName: "Gemini CLI"))
        }

        // Bridge web detection deferred to Phase 4 per spec.

        return BrandDetection(brand: .google, signals: signals)
    }

    private func detectCopilot() async -> BrandDetection? {
        // Copilot stores tokens in the system keyring via gh CLI — we check
        // whether `gh auth status` exits 0, which confirms both installation
        // and authentication without reading the token value.
        let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        guard let ghPath = ghPaths.first(where: { fileManager.fileExists(atPath: $0) }) else {
            return BrandDetection(brand: .copilot, signals: [])
        }

        // gh auth status exits 0 if authenticated, non-zero otherwise.
        let authenticated = runProcessExitsZero(
            executable: ghPath,
            arguments: ["auth", "status"]
        )

        var signals: [DetectionSignal] = []
        if authenticated {
            signals.append(.cliCredentials(path: ghPath, displayName: "gh CLI (authenticated)"))
        }

        return BrandDetection(brand: .copilot, signals: signals)
    }

    private func detectCursor() async -> BrandDetection? {
        var signals: [DetectionSignal] = []

        // Cursor bundle ID confirmed via CursorProvider.swift in the codebase.
        if appLookup.isAppPresent(bundleId: "com.todesktop.230313mzl4w4u92") {
            signals.append(.nativeApp(bundleId: "com.todesktop.230313mzl4w4u92", displayName: "Cursor.app"))
        }

        // Also check for the SQLite credentials file that CursorProvider reads.
        // If Cursor has ever been signed in, this file exists.
        let cursorDB = "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        if fileManager.fileExists(atPath: cursorDB) {
            // Only add a CLI signal if the app signal isn't already present — the DB
            // is created by the app, so presence of one implies the other.
            if !signals.contains(where: { if case .nativeApp = $0 { return true }; return false }) {
                signals.append(.cliCredentials(path: cursorDB, displayName: "Cursor data found"))
            }
        }

        return BrandDetection(brand: .cursor, signals: signals)
    }

    // MARK: - Bridge Freshness

    /// Reads ext-side.json from the App Group container and returns the heartbeat
    /// date if the given provider has a snapshot that is fresher than the window.
    ///
    /// Returns nil when the file is absent, unreadable, or stale.
    private func bridgeHeartbeat(for provider: ProviderId) -> Date? {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetDataStore.appGroupId
        ) else { return nil }

        let fileURL = containerURL.appendingPathComponent("ext-side.json")
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder.bridge.decode(ExtSideState.self, from: data)
        else { return nil }

        // Use the snapshot's capturedAt, which reflects when the extension last
        // saw activity from this provider — more accurate than updatedAt, which
        // advances on every bridge IPC call regardless of provider.
        guard let snapshot = state.snapshots[provider.rawValue] else { return nil }
        let age = Date().timeIntervalSince(snapshot.capturedAt)
        guard age <= Self.bridgeFreshnessWindow else { return nil }
        return snapshot.capturedAt
    }

    // MARK: - Subprocess Helper

    /// Runs a process synchronously and returns true if it exits with status 0.
    ///
    /// stderr is suppressed — we only care about exit code, not output.
    private func runProcessExitsZero(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Provider Annotation Adapter

extension Dictionary where Key == BrandId, Value == BrandDetection {
    /// Expands brand-level detections into a per-ProviderId annotation map.
    ///
    /// Every ProviderId in a brand's pool receives the same annotation string
    /// as its brand. MultiSelectStep consumes this shape — do not change the
    /// key type or the calling convention without updating MultiSelectStep.
    var providerAnnotations: [ProviderId: String] {
        var result: [ProviderId: String] = [:]
        for (_, detection) in self {
            guard detection.isDetected else { continue }
            let annotation = detection.annotation
            for providerId in detection.brand.pools {
                result[providerId] = annotation
            }
        }
        return result
    }
}
