import ServiceManagement

/// Thin wrapper around SMAppService for registering/unregistering as a login item.
/// Uses the macOS 13+ API — matches the project's deployment target.
enum LaunchAtLoginService {

    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item.
    /// Errors are non-fatal: if registration fails the toggle stays consistent
    /// because `isEnabled` re-reads the live SMAppService status.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // SMAppService errors (e.g. user denied in System Settings) are
            // surfaced silently here — the caller re-reads isEnabled so the
            // toggle snaps back to the true state rather than showing stale UI.
        }
    }
}
