import Foundation

/// Debug-only fake detection states for screenshot capture.
///
/// Launch with `-detectionScenario fresh` or `-detectionScenario installed`
/// to make every provider report a first-run connection state regardless of
/// what is actually on the machine (keychain credentials, `gh` auth, and
/// Cursor's local data can't be hidden by a `$HOME` override alone).
///
/// Honored only when `BuildInfo.showsDebugTools` is true; `.real` (the
/// default, and the only value in stable builds) leaves behavior untouched.
enum DetectionScenario: String, Sendable {
    /// Normal behavior — probe the machine.
    case real
    /// Clean Mac: nothing installed, nothing connected.
    case fresh
    /// Tools present but nothing signed in / connected.
    case installed

    static var current: DetectionScenario {
        guard BuildInfo.showsDebugTools,
              let raw = UserDefaults.standard.string(forKey: "detectionScenario"),
              let scenario = DetectionScenario(rawValue: raw) else { return .real }
        return scenario
    }

    /// The connection state every provider reports under this scenario,
    /// or nil to run the provider's real probe.
    var forcedConnection: ProviderConnectionState? {
        switch self {
        case .real: return nil
        case .fresh: return .notInstalled
        case .installed: return .installedNoAuth
        }
    }
}
