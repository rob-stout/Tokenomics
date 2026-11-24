import XCTest
@testable import Tokenomics

// MARK: - NMHManifestInstallerTests
//
// All file operations use a temp directory to avoid touching the real
// ~/Library/Application Support directories.

final class NMHManifestInstallerTests: XCTestCase {

    private var tempAppSupport: URL!

    override func setUp() {
        super.setUp()
        tempAppSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("NMHTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempAppSupport, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempAppSupport)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Runs installAll() pointed at the temp directory.
    private func runInstall(bridgePath: String = "/Applications/Tokenomics.app/Contents/Helpers/TokenomicsBridge") -> NMHManifestInstaller.InstallResult {
        NMHManifestInstallerTestShim.installAll(
            appSupportURL: tempAppSupport,
            bridgePath: bridgePath
        )
    }

    // MARK: - Translocation Guard

    func testTranslocationGuard_skipsAllWrites() {
        // The real installAll() checks Bundle.main.bundleURL.path, which we can't
        // fake in unit tests without method swizzling. Instead we test the guard
        // logic through the testable shim (see NMHManifestInstallerTestShim below).
        let result = NMHManifestInstallerTestShim.installAll(
            appSupportURL: tempAppSupport,
            bridgePath: "/var/folders/AppTranslocation/abc123/d/Tokenomics.app/Contents/Helpers/TokenomicsBridge",
            simulateTranslocation: true
        )
        XCTAssertEqual(result.written, 0, "Translocation guard must prevent all writes")
        XCTAssertEqual(result.skipped, 1, "Should return one skip sentinel for translocation")
        XCTAssertEqual(result.failed, 0)

        // Confirm no files were written
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: tempAppSupport.path)) ?? []
        XCTAssertTrue(entries.isEmpty, "No files should have been written under translocation")
    }

    // MARK: - Idempotency

    func testFirstInstall_writes8Manifests() {
        let result = runInstall()
        XCTAssertEqual(result.written, 8, "First install should write all 8 manifests")
        XCTAssertEqual(result.unchanged, 0)
        XCTAssertEqual(result.failed, 0)
    }

    func testSecondInstall_allUnchanged() {
        _ = runInstall()
        let second = runInstall()
        XCTAssertEqual(second.written, 0, "Second install should find all manifests unchanged")
        XCTAssertEqual(second.unchanged, 8)
        XCTAssertEqual(second.failed, 0)
    }

    // MARK: - Stale Overwrite

    func testStaleManifest_overwrittenWithCorrectPath() throws {
        // Write an initial manifest with an old bridge path
        let oldPath = "/old/path/TokenomicsBridge"
        _ = NMHManifestInstallerTestShim.installAll(
            appSupportURL: tempAppSupport,
            bridgePath: oldPath
        )

        // Now install again with the correct path
        let newPath = "/Applications/Tokenomics.app/Contents/Helpers/TokenomicsBridge"
        let result = NMHManifestInstallerTestShim.installAll(
            appSupportURL: tempAppSupport,
            bridgePath: newPath
        )

        XCTAssertEqual(result.written, 8, "All 8 manifests should be overwritten when path changes")
        XCTAssertEqual(result.unchanged, 0)

        // Verify content of first manifest has the new path
        let firstURL = NMHManifestInstaller.browserManifestURLs(appSupportURL: tempAppSupport).first!.url
        let data = try Data(contentsOf: firstURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["path"] as? String, newPath)
    }

    // MARK: - Browser Path Computation

    func testBrowserManifestURLs_returns8Entries() {
        let entries = NMHManifestInstaller.browserManifestURLs(appSupportURL: tempAppSupport)
        XCTAssertEqual(entries.count, 8)
    }

    func testBrowserManifestURLs_containsExpectedBrowsers() {
        let entries = NMHManifestInstaller.browserManifestURLs(appSupportURL: tempAppSupport)
        let names = entries.map(\.browserName)

        XCTAssertTrue(names.contains("Google Chrome"))
        XCTAssertTrue(names.contains("Google Chrome Beta"))
        XCTAssertTrue(names.contains("Google Chrome Canary"))
        XCTAssertTrue(names.contains("Microsoft Edge"))
        XCTAssertTrue(names.contains("Brave"))
        XCTAssertTrue(names.contains("Vivaldi"))
        XCTAssertTrue(names.contains("Opera"))
        XCTAssertTrue(names.contains("Arc"))
    }

    func testBrowserManifestURLs_allEndWithManifestFileName() {
        let entries = NMHManifestInstaller.browserManifestURLs(appSupportURL: tempAppSupport)
        for entry in entries {
            XCTAssertEqual(entry.url.lastPathComponent, NMHManifestInstaller.manifestFileName,
                           "URL for \(entry.browserName) must end with the manifest file name")
        }
    }

    func testBrowserManifestURLs_chromePathContainsExpectedSubpath() {
        let entries = NMHManifestInstaller.browserManifestURLs(appSupportURL: tempAppSupport)
        let chrome = entries.first { $0.browserName == "Google Chrome" }!
        XCTAssertTrue(chrome.url.path.contains("Google/Chrome/NativeMessagingHosts"))
    }

    // MARK: - Manifest Content

    func testManifestContent_containsCorrectFields() throws {
        _ = runInstall()
        let firstURL = NMHManifestInstaller.browserManifestURLs(appSupportURL: tempAppSupport).first!.url
        let data = try Data(contentsOf: firstURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["name"] as? String, "com.tokenomics.bridge")
        XCTAssertEqual(json["type"] as? String, "stdio")
        XCTAssertNotNil(json["path"])
        XCTAssertNotNil(json["allowed_origins"])
    }

    func testManifestContent_allowedOriginsContainsDevExtensionId() throws {
        _ = runInstall()
        let firstURL = NMHManifestInstaller.browserManifestURLs(appSupportURL: tempAppSupport).first!.url
        let data = try Data(contentsOf: firstURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let origins = json["allowed_origins"] as? [String] ?? []
        XCTAssertTrue(origins.contains("chrome-extension://gcjaebikgcbccgbnbcimccflcgoeefio/"))
        XCTAssertTrue(origins.contains("chrome-extension://nolficmmhjkgmoclepbclpmefilhlejl/"))
    }
}

// MARK: - NMHManifestInstallerTestShim
//
// Thin wrapper that lets tests inject a custom appSupportURL and bridge path,
// bypassing Bundle.main and FileManager's real Application Support URL.

enum NMHManifestInstallerTestShim {

    static func installAll(
        appSupportURL: URL,
        bridgePath: String,
        simulateTranslocation: Bool = false
    ) -> NMHManifestInstaller.InstallResult {

        if simulateTranslocation || bridgePath.contains("/AppTranslocation/") {
            var result = NMHManifestInstaller.InstallResult()
            result.skipped = 1
            return result
        }

        let manifest = buildManifest(bridgePath: bridgePath)

        var result = NMHManifestInstaller.InstallResult()
        for (browserName, url) in NMHManifestInstaller.browserManifestURLs(appSupportURL: appSupportURL) {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            if let existing = try? Data(contentsOf: url), existing == manifest {
                result.unchanged += 1
                result.perBrowser.append((browserName: browserName, result: .unchanged))
            } else {
                do {
                    try manifest.write(to: url, options: .atomic)
                    result.written += 1
                    result.perBrowser.append((browserName: browserName, result: .written))
                } catch {
                    result.failed += 1
                    result.perBrowser.append((browserName: browserName, result: .failed(error)))
                }
            }
        }
        return result
    }

    private static func buildManifest(bridgePath: String) -> Data {
        let manifest: [String: Any] = [
            "name": NMHManifestInstaller.hostName,
            "description": "Tokenomics Web Companion bridge",
            "path": bridgePath,
            "type": "stdio",
            "allowed_origins": NMHManifestInstaller.allowedOrigins,
        ]
        return (try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}
