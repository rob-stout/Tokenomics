import Foundation
import UserNotifications
import os

// MARK: - Alert State

/// Per-(provider, window) state machine for hysteresis
private enum AlertState {
    /// Watching for threshold crossing upward
    case idle
    /// Notification already sent; waiting for utilization to drop below (threshold - 10%) before re-arming
    case alerted
}

// MARK: - NotificationService

/// Evaluates usage snapshots against per-provider thresholds and fires
/// macOS UserNotifications with hysteresis so the user isn't spammed.
///
/// Alert lifecycle per (provider, window):
/// - IDLE → fires notification → ALERTED when utilization ≥ threshold
/// - ALERTED → resets to IDLE when utilization drops below (threshold - 10%)
@MainActor
final class NotificationService: ObservableObject {

    // MARK: - Private State

    /// Keyed by "<providerId>_<windowKey>" to track state per combination
    private var alertStates: [String: AlertState] = [:]

    /// Whether we've already received notification permission (or attempted to)
    private var permissionStatus: UNAuthorizationStatus = .notDetermined

    private let logger = Logger(subsystem: "com.robstout.tokenomics", category: "NotificationService")

    // MARK: - Init

    init() {
        Task { await refreshPermissionStatus() }
    }

    // MARK: - Public API

    /// Evaluate a fresh usage snapshot and fire notifications as appropriate.
    ///
    /// This should be called after every successful provider fetch.
    /// It is a no-op for providers in `authExpired` or `notInstalled`/`installedNoAuth` states.
    func evaluate(
        providerId: ProviderId,
        snapshot: ProviderUsageSnapshot,
        connection: ProviderConnectionState
    ) {
        // Skip disconnected / expired providers — nothing meaningful to report
        guard connection.isConnected else { return }

        let config = SettingsService.notificationConfig(for: providerId)
        guard config.isEnabled else { return }

        let alertWindow = SettingsService.alertWindow

        switch alertWindow {
        case .short:
            evaluateWindow(
                providerId: providerId,
                window: snapshot.shortWindow,
                windowKey: "short",
                config: config
            )
        case .long:
            evaluateWindow(
                providerId: providerId,
                window: snapshot.longWindow,
                windowKey: "long",
                config: config
            )
        case .both:
            evaluateWindow(
                providerId: providerId,
                window: snapshot.shortWindow,
                windowKey: "short",
                config: config
            )
            evaluateWindow(
                providerId: providerId,
                window: snapshot.longWindow,
                windowKey: "long",
                config: config
            )
        }
    }

    // MARK: - Private

    private func evaluateWindow(
        providerId: ProviderId,
        window: WindowUsage,
        windowKey: String,
        config: SettingsService.NotificationConfig
    ) {
        let stateKey = "\(providerId.rawValue)_\(windowKey)"
        let currentState = alertStates[stateKey] ?? .idle
        let utilization = window.utilization
        let threshold = Double(config.threshold)
        let hysteresisFloor = threshold - 10.0

        switch currentState {
        case .idle:
            if utilization >= threshold {
                alertStates[stateKey] = .alerted
                logger.debug("Threshold crossed for \(providerId.rawValue)/\(windowKey): \(utilization)% >= \(threshold)%")
                fireNotification(
                    providerId: providerId,
                    window: window,
                    windowKey: windowKey,
                    utilization: utilization
                )
            }

        case .alerted:
            if utilization < hysteresisFloor {
                // Usage has dropped enough — re-arm for the next crossing
                alertStates[stateKey] = .idle
                logger.debug("Re-armed \(providerId.rawValue)/\(windowKey): \(utilization)% < \(hysteresisFloor)%")
            }
        }
    }

    private func fireNotification(
        providerId: ProviderId,
        window: WindowUsage,
        windowKey: String,
        utilization: Double
    ) {
        Task {
            // Request permission lazily — only when we actually need to fire
            guard await ensurePermission() else {
                logger.info("Notification skipped — permission not granted for \(providerId.rawValue)")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "\(providerId.displayName) at \(Int(utilization))%"
            content.subtitle = window.label
            content.body = "\(window.timeUntilReset). You may hit your limit soon."
            content.categoryIdentifier = "USAGE_ALERT"

            // Stable identifier prevents duplicate banners for the same provider+window
            let identifier = "\(providerId.rawValue)_\(windowKey)_alert"

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil // deliver immediately
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
                logger.info("Notification fired: \(identifier)")
            } catch {
                logger.error("Failed to deliver notification \(identifier): \(error)")
            }
        }
    }

    /// Returns `true` if notifications are (or become) authorized.
    /// Requests authorization the first time it is needed.
    private func ensurePermission() async -> Bool {
        await refreshPermissionStatus()

        switch permissionStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
                permissionStatus = granted ? .authorized : .denied
                logger.info("Notification permission request result: granted=\(granted)")
                return granted
            } catch {
                logger.error("Permission request threw: \(error)")
                return false
            }
        case .denied, .ephemeral:
            return false
        @unknown default:
            return false
        }
    }

    private func refreshPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = settings.authorizationStatus
    }
}
