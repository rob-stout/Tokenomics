import Sparkle
import SwiftUI
import UserNotifications
import WidgetKit

/// Bridges Sparkle's SPUUpdater into SwiftUI as an observable object.
/// Implements gentle reminders for background (LSUIElement) apps so
/// update alerts surface inside the popover instead of getting buried.
/// Persists the "an update is pending" flag across app restarts so the blue
/// dot on Settings / Check for Updates doesn't disappear when the user quits.
///
/// Extracted from `UpdaterService` so the logic can be unit-tested without
/// spinning up Sparkle. Works against any `UserDefaults` instance, including
/// a disposable one used by tests.
struct PendingUpdateStore {
    static let defaultKey = "PendingUpdateVersion"

    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = PendingUpdateStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Record that `version` is available to install.
    func mark(version: String) {
        defaults.set(version, forKey: key)
    }

    /// Forget any stored pending version (user installed or skipped).
    func clear() {
        defaults.removeObject(forKey: key)
    }

    /// Decide whether the dot should be shown on launch.
    ///
    /// Returns `true` if a stored pending version exists and is strictly newer
    /// than `currentVersion`. If the stored version is stale (equal or older
    /// than what's now installed), clears it as a side effect and returns `false`.
    func shouldShowBadge(currentVersion: String) -> Bool {
        guard let pending = defaults.string(forKey: key) else { return false }
        if pending.compare(currentVersion, options: .numeric) == .orderedDescending {
            return true
        }
        defaults.removeObject(forKey: key)
        return false
    }
}

@MainActor
final class UpdaterService: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var updaterController: SPUStandardUpdaterController!
    private let pendingStore = PendingUpdateStore()

    @Published var canCheckForUpdates = false
    @Published var updateAvailable = false

    override init() {
        super.init()

        // Pass self as both updaterDelegate (for post-install hooks) and userDriverDelegate (for gentle reminders)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )

        // Clear stale SUAutomaticallyUpdate = 0 that can persist from first-launch
        // when Sparkle's opt-in dialog never showed (common in LSUIElement apps)
        UserDefaults.standard.removeObject(forKey: "SUAutomaticallyUpdate")

        // Ensure automatic checks are enabled (overrides any stale UserDefaults preference)
        updaterController.updater.automaticallyChecksForUpdates = true

        // Observe Sparkle's canCheckForUpdates property via KVO
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        let current = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        updateAvailable = pendingStore.shouldShowBadge(currentVersion: current)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: - Pending update persistence

    private func markPendingUpdate(_ version: String) {
        pendingStore.mark(version: version)
        updateAvailable = true
    }

    private func clearPendingUpdate() {
        pendingStore.clear()
        updateAvailable = false
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Persist the badge so the dot survives quit/relaunch
        markPendingUpdate(update.displayVersionString)

        // If Sparkle wants immediate focus, let it show the native alert
        if immediateFocus { return true }

        // Send a system notification so the user knows without opening the popover
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Tokenomics Update Available"
        content.body = "Version \(update.displayVersionString) is ready to install."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "sparkle-update-\(update.versionString)",
            content: content,
            trigger: nil
        )
        center.add(request)

        return false
    }

    /// Called right before Sparkle shows the update dialog. LSUIElement apps
    /// need to be explicitly activated or the dialog appears behind other windows.
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        markPendingUpdate(update.displayVersionString)
        guard handleShowingUpdate else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        // Keep the dot visible until the user explicitly installs or skips
    }

    func standardUserDriverWillFinishUpdateSession() {
        // Return to menu-bar-only mode after the update dialog closes
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - SPUUpdaterDelegate

    /// Reload widgets after Sparkle installs an update so the new widget extension is picked up
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard error == nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Clear the persistent dot when the user installs or skips. "Remind Me Later"
    /// (dismiss) leaves the dot in place so they see it again on next launch.
    nonisolated func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let shouldClear = (choice == .install || choice == .skip)
        guard shouldClear else { return }
        Task { @MainActor in
            self.clearPendingUpdate()
        }
    }
}
