import Sparkle
import SwiftUI

/// Bridges Sparkle's SPUUpdater into SwiftUI as an observable object.
/// Owns the updater lifecycle and exposes a simple "check for updates" action.
@MainActor
final class UpdaterService: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe Sparkle's canCheckForUpdates property via KVO
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
