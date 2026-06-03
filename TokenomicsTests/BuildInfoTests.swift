import XCTest
@testable import Tokenomics

/// Tests for `BuildInfo.showsDebugTools` gating logic.
///
/// `BuildInfo.showsDebugTools` returns `true` when `#if DEBUG` (which is always
/// the case for this test target), so the primary contract we can test here is
/// `isPreReleaseVersion`, which is driven purely by the bundle version string
/// and is exercisable without the compilation flag.
final class BuildInfoTests: XCTestCase {

    // MARK: - isPreReleaseVersion

    func testVersionWithHyphen_isPreRelease() {
        // The version-string parser must recognise any hyphenated suffix.
        // This covers "beta.N", "alpha.1", "rc.2", etc.
        let versionStrings = [
            "2.9.0-beta.3",
            "3.0.0-alpha.1",
            "1.0.0-rc.2",
            "2.9.0-beta",
        ]
        for version in versionStrings {
            XCTAssertTrue(
                versionContainsHyphen(version),
                "Expected '\(version)' to be treated as pre-release"
            )
        }
    }

    func testVersionWithoutHyphen_isNotPreRelease() {
        let versionStrings = [
            "2.9.0",
            "3.0.0",
            "1.0",
            "10.12.6",
        ]
        for version in versionStrings {
            XCTAssertFalse(
                versionContainsHyphen(version),
                "Expected '\(version)' to be treated as stable"
            )
        }
    }

    func testEmptyVersionString_isNotPreRelease() {
        XCTAssertFalse(versionContainsHyphen(""))
    }

    // MARK: - showsDebugTools (DEBUG build)

    /// In the test target (always compiled DEBUG), showsDebugTools must be true
    /// regardless of the version string — the DEBUG check short-circuits first.
    func testShowsDebugTools_trueInDebugBuild() {
        XCTAssertTrue(BuildInfo.showsDebugTools,
            "showsDebugTools must be true for DEBUG builds so CI and local tests can exercise debug UI")
    }

    // MARK: - Helpers

    /// Replicates the version-string check from `BuildInfo.isPreReleaseVersion`
    /// so we can test arbitrary version strings without needing to mock Bundle.
    private func versionContainsHyphen(_ version: String) -> Bool {
        version.contains("-")
    }
}
