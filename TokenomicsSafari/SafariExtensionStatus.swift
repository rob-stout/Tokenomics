import Foundation
import SafariServices
import os

// MARK: - SafariExtensionStatus

/// Drives the companion window's enable-screen. Tracks two things:
///   1. Whether the user has switched the Safari extension on
///      (`SFSafariExtensionManager`).
///   2. How recently the bridge last heard from it (`ext-side.json`'s
///      `updatedAt`, read straight from the App Group container).
///
/// This is a rarely-open utility window, not an always-running service, so a
/// light polling timer while the window is visible is simpler and sufficient
/// — no need for the main app's FSEvents watch (`WebCompanionService`).
@MainActor
@Observable
final class SafariExtensionStatus {

    /// Must match `TokenomicsSafariExtension`'s bundle id in project.yml.
    static let extensionIdentifier = "com.robstout.tokenomics.safari.extension"

    enum ExtensionState {
        case unknown
        case disabled
        case enabled
    }

    private(set) var extensionState: ExtensionState = .unknown
    private(set) var lastHeartbeatAt: Date?

    private static let log = Logger(subsystem: "com.robstout.tokenomics.safari", category: "SafariExtensionStatus")

    /// Refresh cadence while the window is on-screen. The bridge writes a
    /// heartbeat roughly every minute (extension alarm) plus on every usage
    /// snapshot, so a few-second poll keeps the status feeling "live" without
    /// meaningfully increasing I/O.
    private static let refreshInterval: TimeInterval = 5

    private var refreshTimer: Timer?

    // MARK: - Lifecycle

    func startObserving() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
    }

    func stopObserving() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Refresh

    func refresh() {
        lastHeartbeatAt = Self.readHeartbeat()

        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Self.extensionIdentifier) { [weak self] state, error in
            if let error {
                Self.log.error("getStateOfSafariExtension failed: \(error.localizedDescription)")
            }
            let isEnabled = state?.isEnabled ?? false
            Task { @MainActor in
                self?.extensionState = isEnabled ? .enabled : .disabled
            }
        }
    }

    // MARK: - Actions

    func openSafariExtensionPreferences() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: Self.extensionIdentifier) { error in
            if let error {
                Self.log.error("showPreferencesForExtension failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - App Group heartbeat

    /// Reads `ext-side.json`'s `updatedAt` directly from the App Group
    /// container via `BridgeFileIO` (shared with the stdio bridge and the
    /// Safari extension handler — see `TokenomicsBridge/BridgeCore.swift`).
    private static func readHeartbeat() -> Date? {
        guard let container = BridgeFileIO.sandboxedContainerURL() else { return nil }
        return BridgeFileIO.readExtSideState(from: container)?.updatedAt
    }
}
