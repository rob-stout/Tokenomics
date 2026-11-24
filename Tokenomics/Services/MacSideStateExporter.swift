import Foundation
import os
import Darwin

// MARK: - MacSideStateExporter

/// Maintains the current Mac-side view of native provider state and writes it to
/// `mac-side.json` in the App Group container on a 250ms debounce.
///
/// All mutation methods are async and isolated to this actor. Rapid updates
/// coalesce to a single disk write.
///
/// Atomic write strategy: write to a `.tmp.<pid>` file, then rename into place.
/// The flock on `bridge.lock` prevents the bridge process from reading a
/// partially-written file when both parties are active simultaneously.
actor MacSideStateExporter {

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "MacSideStateExporter")

    // MARK: - Init

    /// - Parameters:
    ///   - containerURL: The Chromium bridge directory (primary; also where state is reloaded
    ///     from). Pass a temp directory in tests.
    ///   - mirrorURLs: Extra directories that get the same file — the App Group container,
    ///     because the sandboxed Safari extension can't read anywhere else.
    init(containerURL: URL? = BridgeFileIO.containerURL(), mirrorURLs: [URL] = []) {
        self.containerURL = containerURL
        self.mirrorURLs = mirrorURLs
        // Load existing mac-side.json on startup so state survives relaunches.
        if let url = containerURL {
            self.currentMacSideState = Self.readFromDisk(containerURL: url) ?? Self.emptyState()
        } else {
            self.currentMacSideState = Self.emptyState()
        }
    }

    // MARK: - Public API

    /// Replaces or inserts a native provider snapshot by provider ID.
    func setNativeSnapshot(_ snapshot: BridgeSnapshot) async {
        currentMacSideState.nativeSnapshots[snapshot.provider] = snapshot
        currentMacSideState.updatedAt = Date()
        scheduleWrite()
    }

    /// Removes a native snapshot for the given provider ID string.
    func clearNativeSnapshot(provider: String) async {
        guard currentMacSideState.nativeSnapshots[provider] != nil else { return }
        currentMacSideState.nativeSnapshots.removeValue(forKey: provider)
        currentMacSideState.updatedAt = Date()
        scheduleWrite()
    }

    /// Updates the per-provider visibility setting.
    func setVisibility(_ visibility: ProviderVisibilitySetting, for providerId: String) async {
        currentMacSideState.providerVisibility[providerId] = visibility
        currentMacSideState.updatedAt = Date()
        scheduleWrite()
    }

    /// Updates the tab order the extension should follow (it adopts it only if newer than its own).
    func setProviderOrder(_ setting: ProviderOrderSetting) async {
        guard currentMacSideState.providerOrder != setting else { return }
        currentMacSideState.providerOrder = setting
        currentMacSideState.updatedAt = Date()
        scheduleWrite()
    }

    /// Enqueues a command for the extension, deduplicated by `kind`.
    /// Only one pending command of each `kind` is kept — newer enqueues replace older ones.
    func enqueueCommand(_ command: BridgeCommand) async {
        currentMacSideState.pendingCommands.removeAll { $0.kind == command.kind }
        currentMacSideState.pendingCommands.append(command)
        currentMacSideState.updatedAt = Date()
        scheduleWrite()
    }

    /// Updates the mac app version string embedded in state.
    func setMacAppVersion(_ version: String) async {
        currentMacSideState.macAppVersion = version
        currentMacSideState.updatedAt = Date()
        scheduleWrite()
    }

    /// The timestamp of the last successful disk write. Useful for diagnostics.
    var lastWrittenAt: Date? { _lastWrittenAt }

    // MARK: - Private

    private let containerURL: URL?
    private let mirrorURLs: [URL]
    private var currentMacSideState: MacSideState
    private var _lastWrittenAt: Date?
    private var pendingWriteTask: Task<Void, Never>?

    private func scheduleWrite() {
        pendingWriteTask?.cancel()
        pendingWriteTask = Task {
            // 250ms debounce — rapid updates coalesce to one write
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self.performWrite()
        }
    }

    private func performWrite() async {
        guard let container = containerURL else {
            Self.log.warning("No bridge directory — skipping mac-side.json write")
            return
        }

        let state = currentMacSideState
        let data: Data
        do {
            data = try JSONEncoder.bridge.encode(state)
        } catch {
            Self.log.error("Failed to encode MacSideState: \(error)")
            return
        }

        if write(data, to: container) { _lastWrittenAt = Date() }
        for mirror in mirrorURLs { write(data, to: mirror) }
    }

    @discardableResult
    private func write(_ data: Data, to container: URL) -> Bool {
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let lockPath = container.appendingPathComponent("bridge.lock").path
        let lockFD = open(lockPath, O_RDWR | O_CREAT, 0o666)
        guard lockFD >= 0 else {
            Self.log.error("Failed to open bridge.lock: errno \(errno)")
            return false
        }
        defer {
            flock(lockFD, LOCK_UN)
            close(lockFD)
        }

        guard flock(lockFD, LOCK_EX) == 0 else {
            Self.log.error("flock acquire failed: errno \(errno)")
            return false
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let tmpURL = container.appendingPathComponent("mac-side.json.tmp.\(pid)")
        let destURL = container.appendingPathComponent("mac-side.json")

        do {
            try data.write(to: tmpURL, options: .atomic)
        } catch {
            Self.log.error("Failed to write mac-side.json tmp: \(error)")
            return false
        }

        let result = rename(tmpURL.path, destURL.path)
        if result == 0 {
            Self.log.debug("mac-side.json written (\(data.count) bytes)")
            return true
        }
        Self.log.error("rename mac-side.json failed: errno \(errno)")
        try? FileManager.default.removeItem(at: tmpURL)
        return false
    }

    // MARK: - Helpers

    private static func emptyState() -> MacSideState {
        MacSideState(
            updatedAt: .distantPast,
            macAppVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            nativeSnapshots: [:],
            providerVisibility: [:],
            pendingCommands: []
        )
    }

    private static func readFromDisk(containerURL: URL) -> MacSideState? {
        let url = containerURL.appendingPathComponent("mac-side.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder.bridge.decode(MacSideState.self, from: data)
        } catch {
            log.error("Failed to decode mac-side.json: \(error)")
            return nil
        }
    }
}
