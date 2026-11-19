import Foundation
@testable import Tokenomics

/// Unit tests run inside the app, so `UserDefaults.standard` is the real app's
/// settings. Wrap a test in this to save the given keys, clear them for a clean
/// start, and put the real values back afterwards.
///
/// Tests run in several processes at once, so a file lock keeps two processes
/// from interleaving: otherwise one could save another's test value as "real"
/// and restore that.
final class PreservedDefaults {
    private let keys: [String]
    private var saved: [String: Any] = [:]
    private let lockFD: Int32

    init(keys: [String]) {
        self.keys = keys
        lockFD = open(NSTemporaryDirectory() + "tokenomics-tests-defaults.lock", O_CREAT | O_RDWR, 0o600)
        flock(lockFD, LOCK_EX)
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = defaults.object(forKey: key) { saved[key] = value }
            defaults.removeObject(forKey: key)
        }
    }

    func restore() {
        let defaults = UserDefaults.standard
        for key in keys { defaults.set(saved[key], forKey: key) } // nil removes the key
        flock(lockFD, LOCK_UN)
        close(lockFD)
    }

    /// Keys notification tests write: per-provider alert config, which window
    /// alerts, and the reset-celebration bookkeeping.
    static let notificationKeys: [String] =
        ProviderId.allCases.map { "notificationConfig_\($0.rawValue)" }
        + ["alertWindow", "exhaustedWindows", "pendingResetCelebrations"]
}
