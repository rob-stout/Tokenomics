import Foundation

// MARK: - Connector mode

/// How a connector should render its UI.
enum ConnectorMode: Sendable {
    /// One-screen flow: auto-detect or sign-in. Used for providers where the user
    /// can be connected with a single action (Cursor, Copilot OAuth, Claude direct OAuth).
    case quick

    /// Multi-step in-app guided walkthrough. Used for providers that need a CLI
    /// install or a device-code sign-in surfaced through Tokenomics' own UI.
    case guided
}

// MARK: - Connector step

/// The state machine driving a single provider's "from zero to connected" flow.
///
/// Built on top of `ProviderConnectionState` (`Provider.swift:372`) but adds
/// the in-progress states (downloading / installing / waitingForOAuth) that
/// the new flow needs to surface in UI.
enum ConnectorStep: Sendable, Equatable {
    /// Initial — checking whether the provider is already connected.
    case detecting

    /// Provider is not installed/connected. Show the primary install or sign-in CTA.
    case needsAction

    /// User started an external app install (e.g., Cursor.app from cursor.com).
    /// Polling for the bundle to appear.
    case waitingForExternalApp

    /// Tokenomics is running a hidden CLI install (Guided mode, V1 bundled-Node flow).
    /// `progress` is 0–1 if known, nil for indeterminate.
    case installing(progress: Double?)

    /// OAuth handoff — browser is open. Optional device code for guided flows.
    case awaitingOAuth(code: String?)

    /// Successfully connected.
    case connected(plan: String)

    /// Something went wrong; show recovery affordance.
    case failed(ConnectorError)
}

// MARK: - Connector error

/// Recoverable failures a connector may surface. Each carries a recovery action
/// so the connector view can render a single concrete next-step button.
enum ConnectorError: Sendable, Equatable {
    case oauthCancelled
    case oauthFailed(String)
    case cliInstallFailed(String)
    case detectionTimeout
    case appNotFound(bundleId: String)
    case keychainWriteFailed
    case unknown(String)

    var userFacingMessage: String {
        switch self {
        case .oauthCancelled:
            return "Sign-in was cancelled."
        case .oauthFailed(let detail):
            return "Sign-in didn't complete. \(detail)"
        case .cliInstallFailed(let detail):
            return "Setup couldn't finish. \(detail)"
        case .detectionTimeout:
            return "We didn't detect a sign-in. If you finished signing in, tap Check now."
        case .appNotFound(let bundleId):
            return "We couldn't find that app on your Mac. (\(bundleId))"
        case .keychainWriteFailed:
            return "We couldn't securely store your sign-in. Check Keychain Access permissions."
        case .unknown(let detail):
            return detail
        }
    }

    /// What the recovery button should say. Single concrete action — never a dead end.
    var recoveryActionLabel: String {
        switch self {
        case .oauthCancelled, .oauthFailed: return "Try sign-in again"
        case .cliInstallFailed: return "Try setup again"
        case .detectionTimeout: return "Check now"
        case .appNotFound: return "Show me how"
        case .keychainWriteFailed: return "Try again"
        case .unknown: return "Try again"
        }
    }
}

// MARK: - Connector protocol

/// One concrete connector per provider. Encapsulates the "from zero to connected"
/// state machine and presents a uniform surface to `ConnectorViewModel`.
///
/// Conformers are typically `actor`s so detection/install work runs off the main
/// thread; the view model marshals state back to MainActor.
protocol ProviderConnector: Actor {
    /// Which provider this connector handles.
    nonisolated var id: ProviderId { get }

    /// Which UI mode the view should render.
    nonisolated var mode: ConnectorMode { get }

    /// One-shot detection. Called by the view model on appear and after the user
    /// taps the recovery action. Should return quickly (no long network waits).
    func currentStep() async -> ConnectorStep

    /// Performs the primary action for the current step (e.g., open a download URL,
    /// kick off OAuth, run the bundled CLI install). The view model polls
    /// `currentStep()` afterward to advance the state machine.
    func performPrimaryAction() async

    /// User cancelled or backed out. Connectors should clean up any in-flight work
    /// (kill subprocess, dismiss browser handoff state, etc.).
    func cancel() async
}
