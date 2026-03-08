import Sparkle
import SwiftUI

/// Bridges Sparkle's SPUUpdater into SwiftUI as an observable object.
/// Implements gentle reminders for background (LSUIElement) apps so
/// update alerts surface inside the popover instead of getting buried.
@MainActor
final class UpdaterService: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    private var updaterController: SPUStandardUpdaterController!

    @Published var canCheckForUpdates = false
    @Published var updateAvailable = false

    override init() {
        super.init()

        // Pass self as userDriverDelegate for gentle reminders
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )

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

        // Otherwise, show a gentle reminder in our popover
        updateAvailable = true
        return false
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = false
    }
}
