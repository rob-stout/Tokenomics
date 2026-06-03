import Foundation
import os

// MARK: - NMHManifestInstaller

/// Installs the Native Messaging Host manifest for `com.tokenomics.bridge` into
/// all supported Chromium browser config directories.
///
/// This type is a struct because installation is idempotent and requires no
/// mutable state. Call `installAll()` on every Mac app launch.
struct NMHManifestInstaller {

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "NMHManifestInstaller")

    /// Name of the manifest file written to each browser's NativeMessagingHosts directory.
    static let manifestFileName = "com.tokenomics.bridge.json"

    /// The NMH name string used in the manifest and by the extension.
    static let hostName = "com.tokenomics.bridge"

    /// Dev-keypair extension ID for the unpacked / sideloaded build.
    /// When published to the Chrome Web Store a second entry will be added here.
    static let allowedOrigins = [
        "chrome-extension://gcjaebikgcbccgbnbcimccflcgoeefio/"
    ]

    // MARK: - Result Types

    /// Outcome of a single-browser manifest install attempt.
    enum BrowserResult {
        case written
        case unchanged
        case skipped
        case failed(Error)
    }

    /// Aggregate result across all supported browsers.
    struct InstallResult {
        var written: Int = 0
        var unchanged: Int = 0
        var skipped: Int = 0
        var failed: Int = 0
        var perBrowser: [(browserName: String, result: BrowserResult)] = []

        enum SkipReason {
            /// Running from a translocated DMG — bundle path is ephemeral.
            case translocated
        }
    }

    // MARK: - Browser Paths

    /// Returns all (browserName, manifestURL) pairs for supported browsers.
    /// Tests can iterate this to verify path computation independently.
    static func browserManifestURLs(appSupportURL: URL) -> [(browserName: String, url: URL)] {
        let relPaths: [(String, String)] = [
            ("Google Chrome",       "Google/Chrome/NativeMessagingHosts"),
            ("Google Chrome Beta",  "Google/Chrome Beta/NativeMessagingHosts"),
            ("Google Chrome Canary","Google/Chrome Canary/NativeMessagingHosts"),
            ("Microsoft Edge",      "Microsoft Edge/NativeMessagingHosts"),
            ("Brave",               "BraveSoftware/Brave-Browser/NativeMessagingHosts"),
            ("Vivaldi",             "Vivaldi/NativeMessagingHosts"),
            ("Opera",               "com.operasoftware.Opera/NativeMessagingHosts"),
            ("Arc",                 "Arc/NativeMessagingHosts"),
        ]
        return relPaths.map { name, rel in
            (name, appSupportURL.appendingPathComponent(rel).appendingPathComponent(manifestFileName))
        }
    }

    // MARK: - Install

    /// Writes the NMH manifest to every supported browser's NativeMessagingHosts directory.
    ///
    /// - Returns: An `InstallResult` with per-browser outcomes.
    /// - Throws: Only if the App Support URL cannot be resolved (extremely unlikely).
    @discardableResult
    static func installAll() throws -> InstallResult {
        // Translocation guard: the bundle lives at an ephemeral path when the user
        // runs directly from a mounted DMG without copying to /Applications.
        // Writing a manifest at that path would break the host as soon as the disk
        // image is unmounted.
        if Bundle.main.bundleURL.path.contains("/AppTranslocation/") {
            log.warning("Running under App Translocation — skipping NMH manifest install")
            var result = InstallResult()
            result.skipped = 1 // sentinel: one skip entry to signal translocation
            return result
        }

        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NMHInstallError.appSupportDirectoryUnavailable
        }

        let bridgePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/TokenomicsBridge")
            .path

        let manifestContent = buildManifestContent(bridgePath: bridgePath)

        var result = InstallResult()

        for (browserName, manifestURL) in browserManifestURLs(appSupportURL: appSupportURL) {
            let browserResult = installManifest(
                to: manifestURL,
                content: manifestContent,
                browserName: browserName
            )
            result.perBrowser.append((browserName: browserName, result: browserResult))
            switch browserResult {
            case .written:   result.written += 1
            case .unchanged: result.unchanged += 1
            case .skipped:   result.skipped += 1
            case .failed:    result.failed += 1
            }
        }

        log.info("NMH manifest install: written=\(result.written) unchanged=\(result.unchanged) failed=\(result.failed)")
        return result
    }

    // MARK: - Uninstall

    /// Removes the NMH manifest from every supported browser's NativeMessagingHosts
    /// directory. Best-effort: missing files are ignored. Used by the in-app
    /// uninstaller so non-Homebrew users don't leave orphaned manifests (which
    /// would point at a now-deleted bridge binary) behind in each browser.
    static func removeAll() {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        for (browserName, manifestURL) in browserManifestURLs(appSupportURL: appSupportURL) {
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
            do {
                try FileManager.default.removeItem(at: manifestURL)
                log.info("Removed NMH manifest for \(browserName)")
            } catch {
                log.error("Failed to remove NMH manifest for \(browserName): \(error)")
            }
        }
    }

    // MARK: - Private Helpers

    private static func installManifest(
        to url: URL,
        content: Data,
        browserName: String
    ) -> BrowserResult {
        let dir = url.deletingLastPathComponent()

        // Create parent directory if absent (browser not installed yet — safe to pre-create)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                log.error("Cannot create NativeMessagingHosts dir for \(browserName): \(error)")
                return .failed(error)
            }
        }

        // Idempotency check: if the existing file matches exactly, skip the write.
        if let existing = try? Data(contentsOf: url), existing == content {
            return .unchanged
        }

        do {
            try content.write(to: url, options: .atomic)
            log.info("Wrote NMH manifest for \(browserName) at \(url.path)")
            return .written
        } catch {
            log.error("Failed to write NMH manifest for \(browserName): \(error)")
            return .failed(error)
        }
    }

    private static func buildManifestContent(bridgePath: String) -> Data {
        // Build as a Dictionary so keys are always sorted (via JSONSerialization options)
        // producing a stable byte sequence for the idempotency check.
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Tokenomics Web Companion bridge",
            "path": bridgePath,
            "type": "stdio",
            "allowed_origins": allowedOrigins,
        ]
        // JSONSerialization with sortedKeys produces a deterministic byte sequence.
        let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        return data ?? Data()
    }
}

// MARK: - Errors

enum NMHInstallError: Error {
    case appSupportDirectoryUnavailable
}
