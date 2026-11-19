import Foundation
import UserNotifications
import os

// MARK: - Notification Center Protocol

/// Seam for injecting a fake UNUserNotificationCenter in integration tests.
/// Production code uses `UNUserNotificationCenter.current()` which cannot be
/// meaningfully overridden in the test process.
protocol NotificationCenterProtocol: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func notificationSettings() async -> UNNotificationSettings
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: NotificationCenterProtocol {}

// MARK: - Alert State

/// Per-(provider, window) state machine for hysteresis
private enum AlertState {
    /// Watching for threshold crossing upward
    case idle
    /// Notification already sent; waiting for utilization to drop below (threshold - 10%) before re-arming
    case alerted
    /// Hit 100% and said so; same re-arm rule as `alerted`
    case limitHit
}

// MARK: - Tab request

/// The provider whose notification was just clicked. The popover opens on its
/// tab instead of the usual pinned / most-used pick.
@MainActor
enum NotificationTabRequest {
    nonisolated static let providerKey = "providerId"
    static var pending: ProviderId?
}

// MARK: - Reset celebration

/// What the popover's celebration screen says: every provider that reset
/// since the popover last opened.
struct ResetCelebration: Equatable {
    struct Reset: Equatable {
        let providerId: ProviderId
        let windowLabel: String
    }
    let resets: [Reset]

    /// "Claude is ready again" / "Codex CLI and Gemini CLI are ready again" /
    /// "Claude, Codex CLI + 2 more are ready again".
    var title: String {
        let names = resets.map(\.providerId.poolLabel)
        switch names.count {
        case 1: return "\(names[0]) is ready again"
        case 2: return "\(names[0]) and \(names[1]) are ready again"
        default: return "\(names[0]), \(names[1]) + \(names.count - 2) more are ready again"
        }
    }

    /// One reset names its window; several just say usage reset.
    var subtitle: String {
        resets.count == 1
            ? "Your \(resets[0].windowLabel) reset. Ready to build!"
            : "Your usage reset. Ready to build!"
    }
}

// MARK: - NotificationService

/// Evaluates usage snapshots against per-provider thresholds and fires
/// macOS UserNotifications with hysteresis so the user isn't spammed.
///
/// Alert lifecycle per (provider, window):
/// - IDLE → fires notification → ALERTED when utilization ≥ threshold
/// - ALERTED → fires a "hit your limit" notification → LIMIT_HIT at 100%
/// - ALERTED / LIMIT_HIT → reset to IDLE when utilization drops below (threshold - 10%)
@MainActor
final class NotificationService: ObservableObject {

    // MARK: - Private State

    /// Keyed by "<providerId>_<windowKey>" to track state per combination
    private var alertStates: [String: AlertState] = [:]

    /// Whether we've already received notification permission (or attempted to)
    private var permissionStatus: UNAuthorizationStatus = .notDetermined

    private let logger = Logger(subsystem: "com.robstout.tokenomics", category: "NotificationService")

    /// The notification center used to post requests. Injected for testing;
    /// defaults to the shared system center.
    private let notificationCenter: any NotificationCenterProtocol

    // MARK: - Init

    init(notificationCenter: (any NotificationCenterProtocol)? = nil) {
        self.notificationCenter = notificationCenter ?? UNUserNotificationCenter.current()
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
        trackExhaustion(providerId: providerId, snapshot: snapshot, config: config)
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
            // Fall back to the short window when the provider has no long window
            if let longWindow = snapshot.longWindow {
                evaluateWindow(
                    providerId: providerId,
                    window: longWindow,
                    windowKey: "long",
                    config: config
                )
            } else {
                evaluateWindow(
                    providerId: providerId,
                    window: snapshot.shortWindow,
                    windowKey: "short",
                    config: config
                )
            }
        case .both:
            evaluateWindow(
                providerId: providerId,
                window: snapshot.shortWindow,
                windowKey: "short",
                config: config
            )
            if let longWindow = snapshot.longWindow {
                evaluateWindow(
                    providerId: providerId,
                    window: longWindow,
                    windowKey: "long",
                    config: config
                )
            }
        }
    }

    // MARK: - Reset celebration

    /// Windows ("<providerId>_<windowKey>") that reached the alert threshold. Persisted so a reset
    /// that lands after a relaunch still gets celebrated.
    private static let exhaustedWindowsKey = "exhaustedWindows"
    /// Providers freed by a reset since the popover last opened ([providerId: window label]).
    /// The next popover open shows the celebration screen for them.
    nonisolated static let pendingCelebrationKey = "pendingResetCelebrations"

    /// Returns the pending celebration once, then clears it.
    func consumePendingCelebration() -> ResetCelebration? {
        let defaults = UserDefaults.standard
        let pending = defaults.dictionary(forKey: Self.pendingCelebrationKey) as? [String: String] ?? [:]
        defaults.removeObject(forKey: Self.pendingCelebrationKey)
        // Fixed provider order so the names read the same way every time.
        let resets = ProviderId.allCases.compactMap { id in
            pending[id.rawValue].map { ResetCelebration.Reset(providerId: id, windowLabel: $0) }
        }
        return resets.isEmpty ? nil : ResetCelebration(resets: resets)
    }

    /// Celebrates only resets the user was waiting on: a window that reached
    /// their alert threshold and has since dropped below half of it (a real
    /// reset, not a rolling window drifting down a point). Ordinary resets
    /// never fire. If another window is still at or over the threshold, the
    /// user is still waiting on it, so we celebrate when that one resets.
    private func trackExhaustion(
        providerId: ProviderId,
        snapshot: ProviderUsageSnapshot,
        config: SettingsService.NotificationConfig
    ) {
        let threshold = Double(config.threshold)
        let defaults = UserDefaults.standard
        var exhausted = Set(defaults.stringArray(forKey: Self.exhaustedWindowsKey) ?? [])
        var windows = [("short", snapshot.shortWindow)]
        if let longWindow = snapshot.longWindow { windows.append(("long", longWindow)) }

        var resetWindow: WindowUsage?
        for (windowKey, window) in windows {
            let key = "\(providerId.rawValue)_\(windowKey)"
            if window.utilization >= threshold {
                exhausted.insert(key)
            } else if window.utilization < threshold / 2, exhausted.remove(key) != nil {
                resetWindow = window
            }
        }
        defaults.set(Array(exhausted), forKey: Self.exhaustedWindowsKey)

        guard let resetWindow, !windows.contains(where: { $0.1.utilization >= threshold }) else { return }
        logger.info("Reset after exhaustion for \(providerId.rawValue) — celebrating")
        var pending = defaults.dictionary(forKey: Self.pendingCelebrationKey) as? [String: String] ?? [:]
        pending[providerId.rawValue] = resetWindow.label
        defaults.set(pending, forKey: Self.pendingCelebrationKey)
        if config.isEnabled { fireResetNotification(providerId: providerId, window: resetWindow) }
    }

    private func fireResetNotification(providerId: ProviderId, window: WindowUsage) {
        Task {
            guard await ensurePermission() else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(providerId.poolLabel) \(window.label) is ready again"
            content.body = "Your usage reset. Ready to build!"
            content.categoryIdentifier = "RESET_ALERT"
            content.userInfo = [NotificationTabRequest.providerKey: providerId.rawValue]
            let identifier = "\(providerId.rawValue)_reset"
            do {
                try await notificationCenter.add(
                    UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
                logger.info("Notification fired: \(identifier)")
            } catch {
                logger.error("Failed to deliver notification \(identifier): \(error)")
            }
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
                // A threshold of 100 lands straight on the limit — one alert, not two.
                alertStates[stateKey] = utilization >= 100 ? .limitHit : .alerted
                logger.debug("Threshold crossed for \(providerId.rawValue)/\(windowKey): \(utilization)% >= \(threshold)%")
                fireNotification(
                    providerId: providerId,
                    window: window,
                    windowKey: windowKey,
                    utilization: utilization
                )
            }

        case .alerted:
            if utilization >= 100 {
                // Already warned; now say why requests stopped.
                alertStates[stateKey] = .limitHit
                fireNotification(
                    providerId: providerId,
                    window: window,
                    windowKey: windowKey,
                    utilization: utilization
                )
            } else if utilization < hysteresisFloor {
                // Usage has dropped enough — re-arm for the next crossing
                alertStates[stateKey] = .idle
                logger.debug("Re-armed \(providerId.rawValue)/\(windowKey): \(utilization)% < \(hysteresisFloor)%")
            }

        case .limitHit:
            if utilization < hysteresisFloor {
                // Usage has dropped enough — re-arm for the next crossing
                alertStates[stateKey] = .idle
                logger.debug("Re-armed \(providerId.rawValue)/\(windowKey): \(utilization)% < \(hysteresisFloor)%")
            }
        }
    }

    /// Usage-alert title. Uses the pool's source-of-truth label (`poolLabel`) so
    /// the notification reads the same as the toggle / popover / widget — e.g.
    /// "Codex CLI at 90%", never the brand-ish "OpenAI at 90%". Pure + static for
    /// unit testing (see `PoolLabelAlignmentTests`). The window name rides in the
    /// title ("Claude 5-Hour Window at 100%") — a subtitle line looked odd.
    nonisolated static func usageAlertTitle(
        for providerId: ProviderId,
        windowLabel: String? = nil,
        utilization: Double
    ) -> String {
        let name = [providerId.poolLabel, windowLabel].compactMap { $0 }.joined(separator: " ")
        return "\(name) at \(Int(utilization))%"
    }

    /// Two lines: what's happening, then when it resets. At 100% the limit is
    /// already hit, so "may hit your limit soon" would be wrong.
    nonisolated static func usageAlertBody(resetText: String, utilization: Double) -> String {
        let headline = utilization >= 100 ? "You've hit your usage limit." : "You may hit your limit soon."
        return "\(headline)\n\(resetText)"
    }

    /// Exactly what a usage alert says. One builder so tests check the real text.
    nonisolated static func usageAlertText(
        for providerId: ProviderId,
        window: WindowUsage,
        utilization: Double
    ) -> (title: String, body: String) {
        (usageAlertTitle(for: providerId, windowLabel: window.label, utilization: utilization),
         usageAlertBody(resetText: window.resetTimeText, utilization: utilization))
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
            let text = Self.usageAlertText(for: providerId, window: window, utilization: utilization)
            content.title = text.title
            content.body = text.body
            content.categoryIdentifier = "USAGE_ALERT"
            content.userInfo = [NotificationTabRequest.providerKey: providerId.rawValue]

            // Stable identifier prevents duplicate banners for the same provider+window
            let identifier = "\(providerId.rawValue)_\(windowKey)_alert"

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil // deliver immediately
            )

            do {
                try await notificationCenter.add(request)
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
                let granted = try await notificationCenter
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
        let settings = await notificationCenter.notificationSettings()
        permissionStatus = settings.authorizationStatus
    }
}
