import Sparkle
import SwiftUI
import UserNotifications
import WidgetKit

/// Bridges Sparkle's SPUUpdater into SwiftUI as an observable object.
/// Implements gentle reminders for background (LSUIElement) apps so
/// update alerts surface inside the popover instead of getting buried.
@MainActor
final class UpdaterService: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var updaterController: SPUStandardUpdaterController!

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
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // If Sparkle wants immediate focus, let it show the native alert
        if immediateFocus { return true }

        // Show badge in our popover
        updateAvailable = true

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

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = false
    }

    // MARK: - SPUUpdaterDelegate

    /// Reload widgets after Sparkle installs an update so the new widget extension is picked up
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard error == nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
