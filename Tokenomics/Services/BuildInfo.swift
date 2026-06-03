import Foundation

/// Runtime build metadata used to gate debug/demo UI.
///
/// The gating rule: debug tools are visible when the build is either
/// (a) a pre-release version string (contains "-", e.g. "2.9.0-beta.3"), OR
/// (b) a DEBUG compilation (#if DEBUG).
///
/// This means the beta DMG (compiled Release but version "2.9.0-beta.3") shows
/// debug tools so Rob can test them, while stable release builds ("2.9.0", also
/// Release) show nothing.
enum BuildInfo {

    /// `true` when debug/demo UI should be shown.
    ///
    /// Returns `true` if the version string from the main bundle contains "-"
    /// (pre-release marker), OR the binary was compiled in DEBUG mode.
    /// Both conditions are evaluated at runtime so no rebuild is required to
    /// distinguish beta from stable — only the version string in project.yml matters.
    static var showsDebugTools: Bool {
        #if DEBUG
        return true
        #else
        return isPreReleaseVersion
        #endif
    }

    /// `true` when `CFBundleShortVersionString` contains a hyphen.
    /// e.g. "2.9.0-beta.3" → true, "2.9.0" → false.
    /// Exposed separately so tests can exercise the version-string logic
    /// independently of the DEBUG compilation flag.
    static var isPreReleaseVersion: Bool {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return false
        }
        return version.contains("-")
    }
}
