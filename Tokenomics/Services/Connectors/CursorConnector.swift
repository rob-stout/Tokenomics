import Foundation
import AppKit
import os

/// Quick-mode connector for Cursor.
///
/// Detection: delegates to `CursorProvider.checkConnection()` which already
/// reads the JWT from Cursor's local SQLite and validates it against the
/// usage API. Three observable states:
///   - app installed + valid auth → `.connected`
///   - app installed, auth missing/invalid → `.needsAction` (CTA: "Open Cursor")
///   - app not installed → `.needsAction` (CTA: "Download Cursor")
///
/// `performPrimaryAction()` either deep-links to the local Cursor app (if
/// installed) or opens cursor.com/downloads in the user's browser. The polling
/// loop in `ConnectorViewModel` then re-checks every 1.5s until the state
/// settles.
actor CursorConnector: ProviderConnector {
    nonisolated let id: ProviderId = .cursor
    nonisolated let mode: ConnectorMode = .quick

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "CursorConnector")
    private static let downloadURL = URL(string: "https://www.cursor.com/downloads")!
    private static let cursorBundleID = "com.todesktop.230313mzl4w4u92"

    private let provider: CursorProvider

    init(provider: CursorProvider = CursorProvider()) {
        self.provider = provider
    }

    func currentStep() async -> ConnectorStep {
        let state = await provider.checkConnection()

        switch state {
        case .connected(let plan):
            return .connected(plan: plan)
        case .notInstalled:
            return .needsAction
        case .installedNoAuth:
            // App is on disk but auth missing — primary action will open Cursor
            // so the user can sign in. Treat as needsAction since the user has
            // a concrete next step.
            return .needsAction
        case .authExpired:
            return .needsAction
        case .unavailable(let reason):
            return .failed(.unknown(reason))
        }
    }

    func performPrimaryAction() async {
        // If Cursor is installed locally, deep-link into it so the user can
        // sign in. Otherwise hand off to the cursor.com download page.
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.cursorBundleID) {
            await openOnMain(appURL)
        } else {
            await openOnMain(Self.downloadURL)
        }
    }

    func cancel() async {
        // No in-flight async work to cancel for Quick-mode Cursor.
    }

    // MARK: - Helpers

    @MainActor
    private func openOnMain(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
