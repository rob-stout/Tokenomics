import Foundation

/// Usage provider for pools the Mac can only learn about through the browser
/// extension (ChatGPT, Gemini app, Midjourney, Grok, Perplexity, Leonardo, Suno, Udio).
///
/// There is nothing to fetch: the extension reads the site, the NMH bridge writes the
/// numbers to `ext-side.json`, and this provider turns the latest reading into the
/// same `ProviderUsageSnapshot` every other provider produces. That is what lets the
/// popover, menu bar rings, widgets and notifications treat web pools like any other.
///
/// Only numbers cross the bridge — never cookies, tokens or page content.
actor WebCompanionProvider: UsageProvider {
    let id: ProviderId

    /// Pools whose only data path is the browser extension, in `ProviderId` order.
    ///
    /// Claude is deliberately absent. The Mac reads Claude Code natively, and claude.ai
    /// draws on the *same* 5-hour / 7-day windows, so the web reading adds no information
    /// for anyone who has Claude Code. A web-only fallback would need to arbitrate
    /// ClaudeProvider's keychain and re-auth states (a revoked login must prompt, not
    /// silently flip sources), and onboarding has no web-only Claude path. The extension's
    /// `claude` snapshot still feeds onboarding detection (`DetectionService`).
    static let webOnlyPools: [ProviderId] = [
        .chatgpt, .geminiConsumer, .midjourney, .leonardo, .suno, .udio, .grok, .perplexity
    ]

    /// Re-reading a small local file is free, so this is just the safety net behind the
    /// event-driven refresh (`UsageViewModel.refreshBridgeProviders`) — it also lets a
    /// reading age from "live" into "stale" without waiting for a new file write.
    let pollInterval: TimeInterval = 60

    private let snapshotReader: @Sendable () -> BridgeSnapshot?
    private let now: @Sendable () -> Date

    /// - Parameters default to production behaviour; tests inject fakes.
    init(
        id: ProviderId,
        snapshotReader: (@Sendable () -> BridgeSnapshot?)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.id = id
        let rawId = id.rawValue
        self.snapshotReader = snapshotReader ?? {
            WebCompanionService.readStateFromAppGroup()?.snapshots[rawId]
        }
        self.now = now
    }

    func checkConnection() async -> ProviderConnectionState {
        if let forced = DetectionScenario.current.forcedConnection { return forced }
        guard let snap = usableSnapshot() else { return .notInstalled }
        return .connected(plan: Self.planLabel(of: snap))
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        guard let snap = usableSnapshot() else { throw AppError.notAuthenticated }
        return Self.map(snap, id: id, now: now())
    }

    private func usableSnapshot() -> BridgeSnapshot? {
        guard let snap = snapshotReader(),
              WebPoolFreshness.isUsable(snap, id: id, now: now()) else { return nil }
        return snap
    }

    // MARK: - Mapping

    static func planLabel(of snap: BridgeSnapshot) -> String {
        snap.planLabel.isEmpty ? "Browser" : snap.planLabel
    }

    /// Wire snapshot (utilization 0...1) → the Mac's model (0...100). Keeps both windows,
    /// `sublabelOverride`, the plan label, `estimated`, and stamps `capturedAt` so the UI
    /// can tell a live reading from the last-known one.
    ///
    /// A long window whose reset has already passed is dropped from a stale reading: its
    /// number is known to be wrong, and a missing bar beats a confidently wrong one.
    static func map(_ snap: BridgeSnapshot, id: ProviderId, now: Date = Date()) -> ProviderUsageSnapshot {
        func window(_ w: BridgeWindow) -> WindowUsage {
            WindowUsage(
                label: w.label,
                // Clamp: 0...999 keeps a malformed reading from blowing up bar layout
                // while still letting "over limit" (>100) through.
                utilization: min(max(w.utilization * 100, 0), 999),
                resetsAt: w.resetsAt,
                windowDuration: w.windowDurationSec,
                sublabelOverride: w.sublabelOverride
            )
        }
        let isLive = WebPoolFreshness.isLive(snap, id: id, now: now)
        let longWindow = snap.longWindow.flatMap { w -> BridgeWindow? in
            (!isLive && w.resetsAt <= now) ? nil : w
        }
        return ProviderUsageSnapshot(
            shortWindow: window(snap.shortWindow),
            longWindow: longWindow.map(window),
            planLabel: planLabel(of: snap),
            extraUsage: nil,
            creditsBalance: nil,
            capturedAt: snap.capturedAt,
            estimated: snap.estimated
        )
    }
}

// MARK: - Freshness policy

/// How long a browser-extension reading stays trustworthy, per pool.
///
/// Two thresholds, because "the extension is reporting right now" and "the last number
/// is still the right number" are different questions:
///
/// - **Live window** — a reading younger than this counts as current. Sized to just over
///   two missed extension polls so one skipped alarm never flips a pool to "stale".
/// - **Retention** — an older reading is still *shown* (marked "Last read Xh ago") rather
///   than dropped, because usage can't go down until the window resets. This keeps the
///   rings and widgets populated when the browser is closed overnight, which is the
///   whole promise of the extension. A reading is discarded earlier if its short window
///   has already reset (the number is then known to be wrong), and always after
///   `retention` so an uninstalled extension doesn't leave ghost pools forever.
enum WebPoolFreshness {
    /// Last-known readings are kept this long once the browser stops reporting.
    static let retention: TimeInterval = 48 * 3600

    /// Per-pool "currently reporting" window.
    ///
    /// Extension cadence (see `extension/src/background.ts`, `content/*`):
    /// - Midjourney, Leonardo, Udio, ElevenLabs poll every 10 min → 25 min (two misses).
    /// - Grok, Perplexity, Claude poll every 5 min; Gemini's page script every 5 min;
    ///   Suno's every 4 min while a suno.com tab is open → 15 min.
    /// - ChatGPT only re-reads when a message is sent (plus a daily plan check), so a
    ///   quiet hour is normal → 30 min, after which the popover notes the reading's age.
    static func liveWindow(for id: ProviderId) -> TimeInterval {
        switch id {
        case .midjourney, .leonardo, .udio, .elevenlabs: return 25 * 60
        case .chatgpt: return 30 * 60
        default: return 15 * 60
        }
    }

    static func age(of snap: BridgeSnapshot, now: Date) -> TimeInterval {
        // A reading stamped slightly in the future (clock skew) is simply "just now".
        max(0, now.timeIntervalSince(snap.capturedAt))
    }

    static func isLive(_ snap: BridgeSnapshot, id: ProviderId, now: Date) -> Bool {
        age(of: snap, now: now) <= liveWindow(for: id)
    }

    /// Whether the Mac should treat the pool as connected and show this reading.
    static func isUsable(_ snap: BridgeSnapshot, id: ProviderId, now: Date) -> Bool {
        if isLive(snap, id: id, now: now) { return true }
        guard age(of: snap, now: now) <= retention else { return false }
        return snap.shortWindow.resetsAt > now
    }

    /// Whether a mapped snapshot is a last-known reading rather than a current one.
    /// Native reads carry no `capturedAt` and are never stale.
    static func isStale(_ usage: ProviderUsageSnapshot, id: ProviderId, now: Date = Date()) -> Bool {
        guard let capturedAt = usage.capturedAt else { return false }
        return now.timeIntervalSince(capturedAt) > liveWindow(for: id)
    }

    /// "12m" / "3h" / "2d" — compact age for the popover note.
    static func ageText(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<3600: return "\(max(1, Int(seconds / 60)))m"
        case ..<(48 * 3600): return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }
}
