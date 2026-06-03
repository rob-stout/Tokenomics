import AppKit
import Foundation
import ServiceManagement
import os

/// One-click, no-Terminal uninstaller for non-technical users.
///
/// Drag-to-Trash leaves a tail behind: the login-item registration, eight
/// browser native-messaging manifests, the app-group container, caches, prefs,
/// and any Keychain items we created. Homebrew users get this cleanup via the
/// cask's `zap` stanza (`brew uninstall --zap`), but DMG users have no Terminal.
/// This service does the same cleanup from inside the app, then moves the app
/// bundle itself to the Trash and quits.
///
/// IMPORTANT: the app is *not* sandboxed (see Tokenomics.entitlements), which is
/// what lets it reach the browser manifests and the bundle in /Applications.
enum UninstallService {

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "UninstallService")

    /// Runs the full cleanup, moves the app to the Trash, and terminates.
    ///
    /// Order matters: clean up external state (login item, manifests, Keychain,
    /// support files) *first* so it's all gone even if the final bundle move
    /// fails; then trash the bundle and quit.
    @MainActor
    static func uninstallAndQuit() {
        unregisterLoginItem()
        NMHManifestInstaller.removeAll()
        removeKeychainItems()
        removeSupportFiles()
        trashBundleAndQuit()
    }

    // MARK: - Login item

    private static func unregisterLoginItem() {
        do {
            try SMAppService.mainApp.unregister()
            log.info("Unregistered login item")
        } catch {
            // Already-unregistered or user-denied — nothing actionable.
            log.error("Login-item unregister failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Keychain

    /// The generic-password Keychain services Tokenomics *created* — the Copilot
    /// PAT and per-provider API keys, all under the `com.robstout.tokenomics`
    /// prefix. Deliberately excludes `Claude Code-credentials`, which belongs to
    /// Claude Code and is merely read by us — deleting it would sign the user out
    /// of Claude Code. Static + internal so it can be unit-tested.
    static var keychainServicesToRemove: [String] {
        ["com.robstout.tokenomics.github-pat"]
            + ProviderId.allCases.map { "com.robstout.tokenomics.apikey.\($0.rawValue)" }
    }

    private static func removeKeychainItems() {
        for service in keychainServicesToRemove {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service
            ]
            SecItemDelete(query as CFDictionary) // errSecItemNotFound is fine
        }
        log.info("Removed Tokenomics-owned Keychain items")
    }

    // MARK: - Support files

    private static func removeSupportFiles() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let lib = home.appendingPathComponent("Library")

        let paths: [URL] = [
            lib.appendingPathComponent("Preferences/com.robstout.tokenomics.plist"),
            lib.appendingPathComponent("Caches/com.robstout.tokenomics"),
            lib.appendingPathComponent("Containers/com.robstout.tokenomics"),
            lib.appendingPathComponent("Containers/com.robstout.tokenomics.widgets"),
            lib.appendingPathComponent("Group Containers/group.com.robstout.tokenomics"),
            lib.appendingPathComponent("HTTPStorages/com.robstout.tokenomics"),
            lib.appendingPathComponent("Application Support/Tokenomics"),
            lib.appendingPathComponent("Logs/Tokenomics"),
        ]

        for url in paths {
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                try fm.removeItem(at: url)
                log.info("Removed \(url.lastPathComponent)")
            } catch {
                log.error("Failed to remove \(url.path): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Bundle + quit

    /// Moves the running .app to the Trash, then terminates. macOS permits moving
    /// a running bundle — the process keeps executing from the relocated copy
    /// until it exits a moment later.
    @MainActor
    private static func trashBundleAndQuit() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([bundleURL]) { _, error in
            if let error {
                Self.log.error("Could not move app to Trash: \(error.localizedDescription)")
            } else {
                Self.log.info("Moved app bundle to Trash")
            }
            // Quit regardless — external state is already cleaned up.
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
