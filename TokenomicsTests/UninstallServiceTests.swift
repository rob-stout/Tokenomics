import XCTest
@testable import Tokenomics

/// Regression tests for the in-app uninstaller's cleanup targets.
///
/// The highest-risk part isn't deleting too little — it's deleting too much.
/// Tokenomics only *reads* Claude Code's Keychain item (`Claude Code-credentials`);
/// the uninstaller must never remove it, or it would sign the user out of Claude
/// Code. These lock the service list down to Tokenomics-owned items.
final class UninstallServiceTests: XCTestCase {

    func testNeverTargetsClaudeCodeCredentials() {
        XCTAssertFalse(
            UninstallService.keychainServicesToRemove.contains("Claude Code-credentials"),
            "Uninstaller must not delete Claude Code's own Keychain item."
        )
    }

    func testAllTargetsAreTokenomicsOwned() {
        for service in UninstallService.keychainServicesToRemove {
            XCTAssertTrue(
                service.hasPrefix("com.robstout.tokenomics"),
                "Unexpected non-Tokenomics Keychain service in removal list: \(service)"
            )
        }
    }

    func testIncludesCopilotPATService() {
        XCTAssertTrue(UninstallService.keychainServicesToRemove
            .contains("com.robstout.tokenomics.github-pat"))
    }

    func testIncludesAPIKeyServicesForApiKeyProviders() {
        // The API-key providers (Stability, Runway, ElevenLabs) store keys we own.
        for provider in [ProviderId.stableDiffusion, .runway, .elevenlabs] {
            XCTAssertTrue(
                UninstallService.keychainServicesToRemove
                    .contains("com.robstout.tokenomics.apikey.\(provider.rawValue)"),
                "Missing API-key service for \(provider.rawValue)"
            )
        }
    }

    func testNoDuplicateServices() {
        let services = UninstallService.keychainServicesToRemove
        XCTAssertEqual(services.count, Set(services).count)
    }

    // MARK: - Browser manifest coverage

    func testManifestRemovalCoversEveryInstalledBrowserPath() {
        // removeAll() iterates the same browserManifestURLs the installer writes,
        // so the orphan-manifest cleanup can't silently miss a browser.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let urls = NMHManifestInstaller.browserManifestURLs(appSupportURL: tmp)
        XCTAssertEqual(urls.count, 8, "Expected manifests for all 8 supported browsers.")
        for (_, url) in urls {
            XCTAssertEqual(url.lastPathComponent, NMHManifestInstaller.manifestFileName)
        }
    }
}
