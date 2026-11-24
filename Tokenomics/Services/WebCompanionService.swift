import Foundation
import os
import WidgetKit

// MARK: - WebCompanionStateProvider

/// The read-only surface of `WebCompanionService` that connectors depend on.
/// Defined as a protocol so tests can substitute a lightweight stub without
/// touching FSEvents or the App Group container.
protocol WebCompanionStateProvider: Actor {
    /// Returns the most-recently cached extension state.
    func currentState() async -> ExtSideState
}

// MARK: - WebCompanionService

/// Reads `ext-side.json` from the bridge directories and exposes the extension's
/// latest state to the Mac app. Watches the container directory via FSEvents so
/// atomic writes (which replace the file inode) are picked up reliably.
///
/// This actor does NOT write any files. Writing `mac-side.json` is
/// MacSideStateExporter's responsibility.
actor WebCompanionService: WebCompanionStateProvider {

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "WebCompanionService")

    // MARK: - Init

    /// - Parameter onRefreshRequested: Called when an incoming ExtSideState signals
    ///   that the extension wants the Mac to re-poll native providers.
    ///   Wired by Agent 5: ConnectorContainer / TokenomicsApp.swift
    /// - Parameter onStateChanged: Called after every reload of `ext-side.json` (FSEvents
    ///   or `handleStateChange`), so the Mac can show new web-pool numbers within about
    ///   a second of the extension writing them instead of waiting for the next poll.
    init(
        onRefreshRequested: (@Sendable () -> Void)? = nil,
        onStateChanged: (@Sendable () -> Void)? = nil,
        directories: [URL]? = nil
    ) {
        self.onRefreshRequested = onRefreshRequested
        self.onStateChanged = onStateChanged
        // Tests pass an empty temp dir so they never read the user's live bridge files.
        self.watchedDirectories = directories ?? Self.sourceDirectories()

        // Read initial state synchronously before FSEvents starts so callers
        // get real data on first access without waiting for a filesystem event.
        self.cachedState = Self.readFromDisk(directories: watchedDirectories)
    }

    // MARK: - Public API

    /// Returns the latest cached ExtSideState. Empty state when the file is absent.
    func currentState() async -> ExtSideState {
        cachedState ?? .empty
    }

    /// Convenience lookup of a snapshot by typed ProviderId.
    func snapshot(for providerId: ProviderId) async -> BridgeSnapshot? {
        cachedState?.snapshots[providerId.rawValue]
    }

    /// The extension's current per-provider visibility view.
    func providerVisibility() async -> [String: ProviderVisibilitySetting] {
        cachedState?.providerVisibility ?? [:]
    }

    // MARK: - FSEvents Watch

    /// Starts watching the App Group container directory. Call once at app launch.
    func startWatching() {
        guard eventStream == nil else { return } // already watching

        let pathArray: CFArray = watchedDirectories.map { $0.path as CFString } as CFArray

        // We capture `self` as an unmanaged reference because FSEventStream
        // C callbacks can't capture Swift actors directly.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<WebCompanionService>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let info = clientCallBackInfo else { return }
            let service = Unmanaged<WebCompanionService>.fromOpaque(info).takeUnretainedValue()

            // Check if any event path mentions ext-side.json
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let relevant = paths.contains { $0.hasSuffix("ext-side.json") }
            guard relevant else { return }

            Task {
                await service.scheduleReload()
            }
        }

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05, // 50ms latency — coalesces rapid writes
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
            self.eventStream = stream
            Self.log.info("FSEvents watch started on \(self.watchedDirectories.map(\.path))")
        } else {
            // Release the retained self if stream creation failed
            Unmanaged<WebCompanionService>.fromOpaque(selfPtr).release()
            Self.log.error("FSEventStreamCreate failed")
        }
    }

    /// Stops FSEvents watch. Safe to call multiple times.
    func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    // MARK: - Internal state-change handling (testable surface)

    /// Pure state-update logic extracted for unit testing. FSEvents glue calls this.
    func handleStateChange(_ newState: ExtSideState) {
        cachedState = newState
        scheduleWidgetReload()
        onStateChanged?()
    }

    // MARK: - Private

    private let onRefreshRequested: (@Sendable () -> Void)?
    private let onStateChanged: (@Sendable () -> Void)?
    /// Chromium bridge dir + Safari's App Group container (see `sourceDirectories()`).
    private let watchedDirectories: [URL]
    private var cachedState: ExtSideState?
    private var eventStream: FSEventStreamRef?

    /// Debounce handle for widget reload — cancels any pending reload before scheduling a new one.
    private var widgetReloadItem: DispatchWorkItem?

    /// Debounce handle for the FSEvents read — coalesces rapid directory events.
    private var reloadTask: Task<Void, Never>?

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            // The 50ms latency on the FSEventStream handles coalescing at the
            // stream level; this Task-based debounce handles any residual bursts.
            guard !Task.isCancelled else { return }
            guard let newState = Self.readFromDisk(directories: watchedDirectories) else { return }
            handleStateChange(newState)
        }
    }

    private func scheduleWidgetReload() {
        widgetReloadItem?.cancel()
        let item = DispatchWorkItem {
            WidgetCenter.shared.reloadAllTimelines()
        }
        widgetReloadItem = item
        // 5-second debounce — last write wins
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: item)
    }

    /// Two writers feed the Mac: the Chromium helper (Application Support — the App
    /// Group container is blocked for processes Chrome launches) and the sandboxed
    /// Safari extension (which can only use the App Group container). Read both.
    nonisolated static func sourceDirectories() -> [URL] {
        var dirs: [URL] = []
        if let chromium = BridgeFileIO.containerURL() { dirs.append(chromium) }
        dirs.append(BridgeFileIO.groupContainerURL())
        return dirs
    }

    /// One-shot read of `ext-side.json` from every source directory, merged, for
    /// callers (providers) that don't hold the live service. Nil when absent/unreadable.
    nonisolated static func readStateFromAppGroup() -> ExtSideState? {
        readFromDisk(directories: sourceDirectories())
    }

    /// Reads each directory's `ext-side.json` and merges them (newest entry per key wins).
    static func readFromDisk(directories: [URL]) -> ExtSideState? {
        BridgeMerger.combine(directories.compactMap { readFromDisk(containerURL: $0) })
    }

    private static func readFromDisk(containerURL: URL) -> ExtSideState? {
        let fileURL = containerURL.appendingPathComponent("ext-side.json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder.bridge.decode(ExtSideState.self, from: data)
        } catch {
            log.error("Failed to decode ext-side.json: \(error)")
            return nil
        }
    }
}

// MARK: - ExtSideState helpers

extension ExtSideState {
    /// Convenience empty state for when the file is absent.
    static var empty: ExtSideState {
        ExtSideState(updatedAt: .distantPast, snapshots: [:], providerVisibility: [:])
    }

    /// Returns true when `updatedAt` is within `window` seconds of `now`.
    /// The bridge writes `updatedAt` on every heartbeat (~60s cadence from the
    /// extension), so "fresh" means the extension connected recently enough to
    /// consider the NMH bridge active.
    func isFresh(at now: Date = Date(), within window: TimeInterval = 300) -> Bool {
        now.timeIntervalSince(updatedAt) <= window
    }

    /// Provider IDs the extension is feeding, for the onboarding "Connected" badge.
    ///
    /// Uses the same rule as the Mac's own connection check (`WebPoolFreshness.isUsable`)
    /// so the badge never disagrees with whether the pool actually shows up in the
    /// popover. The old flat 5-minute window flapped for pools the extension polls every
    /// 10 minutes, or only when you send a ChatGPT message.
    ///
    /// Deliberately checks each snapshot's own `capturedAt`, not the whole-state
    /// `updatedAt` that `isFresh` uses — the bridge heartbeats every ~60s
    /// regardless of which provider's usage it last saw, so a stale provider's
    /// snapshot can sit alongside a fresh `updatedAt`. Used by `ProviderChooserView`
    /// to show "Connected" for extension-fed providers.
    func freshlyConnectedProviderIds(at now: Date = Date()) -> Set<ProviderId> {
        Set(snapshots.compactMap { rawId, snapshot -> ProviderId? in
            guard let id = ProviderId(rawValue: rawId),
                  WebPoolFreshness.isUsable(snapshot, id: id, now: now) else { return nil }
            return id
        })
    }
}
