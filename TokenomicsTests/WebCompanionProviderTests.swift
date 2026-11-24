import XCTest
@testable import Tokenomics

/// Browser-extension-fed pools: wire → Mac mapping, freshness / connection rule,
/// no-echo export guard, and the file-watcher refresh plumbing.
final class WebCompanionProviderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Fixtures

    private func window(
        _ label: String,
        _ utilization: Double,
        resetsIn: TimeInterval = 86_400,
        duration: TimeInterval = 86_400,
        sublabel: String? = nil
    ) -> BridgeWindow {
        BridgeWindow(
            label: label,
            utilization: utilization,
            resetsAt: now.addingTimeInterval(resetsIn),
            windowDurationSec: duration,
            sublabelOverride: sublabel
        )
    }

    private func snapshot(
        _ id: ProviderId,
        age: TimeInterval = 30,
        short: BridgeWindow? = nil,
        long: BridgeWindow? = nil,
        plan: String = "Pro",
        estimated: Bool? = false
    ) -> BridgeSnapshot {
        BridgeSnapshot(
            provider: id.rawValue,
            capturedAt: now.addingTimeInterval(-age),
            estimated: estimated,
            shortWindow: short ?? window("Window", 0.4),
            longWindow: long,
            planLabel: plan
        )
    }

    private func provider(_ id: ProviderId, _ snap: BridgeSnapshot?) -> WebCompanionProvider {
        WebCompanionProvider(id: id, snapshotReader: { snap }, now: { [now] in now })
    }

    // MARK: - Mapping, per pool (shapes mirror what each extension reader emits)

    func testMapping_eachWebPool_scalesUtilizationAndKeepsLabelsAndPlan() throws {
        // (pool, short window, long window, plan)
        let cases: [(ProviderId, BridgeWindow, BridgeWindow?, String)] = [
            (.chatgpt, window("5-Hour", 0.25, duration: 18_000), window("Weekly", 0.5, duration: 604_800), "Plus"),
            (.geminiConsumer, window("5-Hour Window", 0.1, duration: 18_000), window("Weekly Window", 0.2, duration: 604_800), "Gemini"),
            (.midjourney, window("Fast Hours", 0.37, duration: 2_592_000), nil, "Standard"),
            (.grok, window("Daily", 0.8), nil, "Free"),
            (.perplexity, window("Daily", 0.15), nil, "Pro"),
            (.leonardo, window("Tokens", 0.62, duration: 2_592_000), nil, "Apprentice"),
            (.suno, window("Credits", 0.4, duration: 2_592_000, sublabel: "1,500 credits left"), nil, "Pro"),
            (.udio, window("Monthly", 0.01, duration: 2_592_000), window("Daily", 0.2), "Free"),
        ]
        // Guard: the table covers every web-only pool.
        XCTAssertEqual(Set(cases.map(\.0)), Set(WebCompanionProvider.webOnlyPools))

        for (id, short, long, plan) in cases {
            let usage = WebCompanionProvider.map(
                snapshot(id, short: short, long: long, plan: plan), id: id, now: now)
            XCTAssertEqual(usage.shortWindow.utilization, short.utilization * 100, accuracy: 0.0001, "\(id)")
            XCTAssertEqual(usage.shortWindow.label, short.label, "\(id)")
            XCTAssertEqual(usage.shortWindow.windowDuration, short.windowDurationSec, "\(id)")
            XCTAssertEqual(usage.shortWindow.resetsAt, short.resetsAt, "\(id)")
            XCTAssertEqual(usage.shortWindow.sublabelOverride, short.sublabelOverride, "\(id)")
            XCTAssertEqual(usage.longWindow?.label, long?.label, "\(id)")
            XCTAssertEqual(try XCTUnwrap(usage.longWindow?.utilization ?? 0), (long?.utilization ?? 0) * 100, accuracy: 0.0001, "\(id)")
            XCTAssertEqual(usage.planLabel, plan, "\(id)")
        }
    }

    func testMapping_carriesEstimatedAndCaptureTime() {
        let snap = snapshot(.chatgpt, age: 120, estimated: true)
        let usage = WebCompanionProvider.map(snap, id: .chatgpt, now: now)
        XCTAssertEqual(usage.estimated, true)
        XCTAssertEqual(usage.capturedAt, snap.capturedAt)
    }

    func testMapping_emptyPlanFallsBackToBrowser_andUtilizationIsClamped() {
        let snap = snapshot(.grok, short: window("Daily", -0.5), plan: "")
        let usage = WebCompanionProvider.map(snap, id: .grok, now: now)
        XCTAssertEqual(usage.planLabel, "Browser")
        XCTAssertEqual(usage.shortWindow.utilization, 0)
        let over = WebCompanionProvider.map(snapshot(.grok, short: window("Daily", 50)), id: .grok, now: now)
        XCTAssertEqual(over.shortWindow.utilization, 999)
    }

    func testMapping_overLimitStillShows() {
        let usage = WebCompanionProvider.map(snapshot(.grok, short: window("Daily", 1.2)), id: .grok, now: now)
        XCTAssertEqual(usage.shortWindow.utilization, 120, accuracy: 0.0001)
    }

    func testMapping_staleReading_dropsLongWindowThatAlreadyReset() {
        let staleAge: TimeInterval = 5 * 3600
        let snap = snapshot(.chatgpt, age: staleAge,
                            short: window("Weekly", 0.3, resetsIn: 86_400),
                            long: window("5-Hour", 0.9, resetsIn: -3_600))
        let usage = WebCompanionProvider.map(snap, id: .chatgpt, now: now)
        XCTAssertNil(usage.longWindow, "a long window past its reset is known-wrong when the reading is stale")
        // …but a live reading keeps it (the extension may be mid-refresh).
        let live = WebCompanionProvider.map(
            snapshot(.chatgpt, age: 10, short: window("Weekly", 0.3), long: window("5-Hour", 0.9, resetsIn: -60)),
            id: .chatgpt, now: now)
        XCTAssertNotNil(live.longWindow)
    }

    // MARK: - Connection + freshness

    func testConnection_freshReading_connectedWithPlan() async {
        for id in WebCompanionProvider.webOnlyPools {
            let connection = await provider(id, snapshot(id, plan: "Plus")).checkConnection()
            XCTAssertEqual(connection, .connected(plan: "Plus"), "\(id)")
        }
    }

    func testConnection_noReading_notInstalled_andFetchThrows() async {
        let p = provider(.suno, nil)
        let connection = await p.checkConnection()
        XCTAssertEqual(connection, .notInstalled)
        do {
            _ = try await p.fetchUsage()
            XCTFail("expected notAuthenticated")
        } catch {
            guard case AppError.notAuthenticated = error else { return XCTFail("wrong error \(error)") }
        }
    }

    func testFreshness_liveWindowExceedsTwoPollsForEveryPool() {
        // Extension cadence in seconds (background.ts + content scripts). The window must
        // tolerate one missed poll so a skipped alarm never flaps the pool.
        let pollSeconds: [ProviderId: TimeInterval] = [
            .midjourney: 600, .leonardo: 600, .udio: 600, .elevenlabs: 600,
            .grok: 300, .perplexity: 300, .geminiConsumer: 300, .suno: 240,
        ]
        for (id, poll) in pollSeconds {
            XCTAssertGreaterThanOrEqual(WebPoolFreshness.liveWindow(for: id), 2 * poll, "\(id)")
        }
    }

    func testFreshness_slowPoller_liveAt20Minutes_fastPollerIsNot() {
        XCTAssertTrue(WebPoolFreshness.isLive(snapshot(.midjourney, age: 20 * 60), id: .midjourney, now: now))
        XCTAssertFalse(WebPoolFreshness.isLive(snapshot(.grok, age: 20 * 60), id: .grok, now: now))
    }

    func testFreshness_stale_keepsLastKnownNumbersUntilResetOrRetention() async throws {
        // Browser closed 6h: still connected, shows last numbers, marked stale.
        let snap = snapshot(.midjourney, age: 6 * 3600, short: window("Fast Hours", 0.5, resetsIn: 10 * 86_400))
        let p = provider(.midjourney, snap)
        let connection = await p.checkConnection()
        XCTAssertEqual(connection, .connected(plan: "Pro"))
        let usage = try await p.fetchUsage()
        XCTAssertEqual(usage.shortWindow.utilization, 50, accuracy: 0.0001)
        XCTAssertTrue(WebPoolFreshness.isStale(usage, id: .midjourney, now: now))
    }

    func testFreshness_stale_dropsOnceShortWindowHasReset() async {
        let snap = snapshot(.chatgpt, age: 6 * 3600, short: window("5-Hour", 0.9, resetsIn: -3_600))
        let connection = await provider(.chatgpt, snap).checkConnection()
        XCTAssertEqual(connection, .notInstalled, "a stale 90% whose window reset an hour ago is wrong, not last-known")
    }

    func testFreshness_pastRetention_dropped() async {
        let snap = snapshot(.udio, age: WebPoolFreshness.retention + 60,
                            short: window("Monthly", 0.1, resetsIn: 20 * 86_400))
        let connection = await provider(.udio, snap).checkConnection()
        XCTAssertEqual(connection, .notInstalled)
    }

    func testFreshness_futureStampedReading_treatedAsJustNow() {
        let snap = snapshot(.grok, age: -90) // clock skew
        XCTAssertTrue(WebPoolFreshness.isLive(snap, id: .grok, now: now))
    }

    func testStaleness_nativeReadingsAreNeverStale() {
        let native = ProviderUsageSnapshot(
            shortWindow: WindowUsage(label: "5-Hour", utilization: 10, resetsAt: now, windowDuration: 18_000),
            longWindow: nil, planLabel: "Max", extraUsage: nil, creditsBalance: nil)
        XCTAssertFalse(WebPoolFreshness.isStale(native, id: .claude, now: now))
    }

    func testAgeText() {
        XCTAssertEqual(WebPoolFreshness.ageText(since: now.addingTimeInterval(-30), now: now), "1m")
        XCTAssertEqual(WebPoolFreshness.ageText(since: now.addingTimeInterval(-25 * 60), now: now), "25m")
        XCTAssertEqual(WebPoolFreshness.ageText(since: now.addingTimeInterval(-3 * 3600), now: now), "3h")
        XCTAssertEqual(WebPoolFreshness.ageText(since: now.addingTimeInterval(-50 * 3600), now: now), "2d")
    }

    // MARK: - Popover note

    func testWebReadingNote_liveExact_hasNoNote() {
        let usage = WebCompanionProvider.map(snapshot(.grok), id: .grok, now: now)
        XCTAssertNil(PopoverView.webReadingNote(for: usage, providerId: .grok, now: now))
    }

    func testWebReadingNote_staleAndEstimated() {
        let usage = WebCompanionProvider.map(
            snapshot(.chatgpt, age: 3 * 3600, estimated: true), id: .chatgpt, now: now)
        XCTAssertEqual(
            PopoverView.webReadingNote(for: usage, providerId: .chatgpt, now: now),
            "Last read 3h ago · Estimated from your browser activity")
    }

    // MARK: - Scope guards

    func testWebOnlyPools_areExactlyTheBrowserExtensionPools_minusClaude() {
        let extensionPools = Set(ProviderId.allCases.filter { $0.trackingSurface == .browserExtension })
        XCTAssertEqual(Set(WebCompanionProvider.webOnlyPools), extensionPools)
        XCTAssertFalse(WebCompanionProvider.webOnlyPools.contains(.claude),
                       "Claude is native-only: Claude Code and claude.ai share the same windows")
        XCTAssertFalse(WebCompanionProvider.webOnlyPools.contains(.elevenlabs),
                       "ElevenLabs is dual-source and has its own provider")
    }

    func testWebPools_sitUnderTheirBrandsNextToTheNativePool() {
        XCTAssertEqual(ProviderId.chatgpt.brand, .openai)
        XCTAssertTrue(BrandId.openai.pools.contains(.codex))
        XCTAssertEqual(ProviderId.geminiConsumer.brand, .google)
        XCTAssertTrue(BrandId.google.pools.contains(.gemini))
    }

    // MARK: - No echo

    func testNoEcho_webPoolsAreAlwaysBridgeSourced() async {
        for id in WebCompanionProvider.webOnlyPools {
            let sourced = await UsageViewModel.isBridgeSourced(provider(id, snapshot(id)))
            XCTAssertTrue(sourced, "\(id) readings must never be exported back as native")
        }
    }

    func testNoEcho_elevenLabsOnlyWhenBridgeProducedIt_andClaudeNever() async throws {
        let bridge = snapshot(.elevenlabs)
        let viaBridge = ElevenLabsProvider(
            apiKeyReader: { nil }, bridgeSnapshotReader: { bridge }, now: { [now] in now })
        _ = try await viaBridge.fetchUsage()
        let bridgeSourced = await UsageViewModel.isBridgeSourced(viaBridge)
        XCTAssertTrue(bridgeSourced)

        let viaKey = ElevenLabsProvider(
            apiKeyReader: { "sk" }, bridgeSnapshotReader: { bridge },
            subscriptionFetcher: { _ in
                ElevenLabsSubscription(tier: "pro", characterCount: 1, characterLimit: 10, nextCharacterCountResetUnix: nil)
            }, now: { [now] in now })
        _ = try await viaKey.fetchUsage()
        let keySourced = await UsageViewModel.isBridgeSourced(viaKey)
        XCTAssertFalse(keySourced)

        let claudeSourced = await UsageViewModel.isBridgeSourced(ClaudeProvider())
        XCTAssertFalse(claudeSourced)
    }

    func testElevenLabs_isBridgeFedOnlyWithoutAKey() async {
        let noKey = ElevenLabsProvider(apiKeyReader: { nil }, bridgeSnapshotReader: { nil })
        let fedNoKey = await noKey.isBridgeFed
        XCTAssertTrue(fedNoKey)
        let withKey = ElevenLabsProvider(apiKeyReader: { "k" }, bridgeSnapshotReader: { nil })
        let fedWithKey = await withKey.isBridgeFed
        XCTAssertFalse(fedWithKey)
    }

    // MARK: - File-watcher refresh

    func testStateChange_firesCallback_soTheMacCanRefreshImmediately() async {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func bump() { lock.lock(); n += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return n }
        }
        let counter = Counter()
        let service = WebCompanionService(onStateChanged: { counter.bump() })
        await service.handleStateChange(ExtSideState(updatedAt: now, snapshots: [:], providerVisibility: [:]))
        await service.handleStateChange(ExtSideState(updatedAt: now, snapshots: [:], providerVisibility: [:]))
        XCTAssertEqual(counter.value, 2)
    }

    func testBridgeStateDiffers_onlyWhenTheReadingOrConnectionChanged() {
        func state(_ capturedAt: Date?, connected: Bool = true) -> ProviderState {
            ProviderState(
                connection: connected ? .connected(plan: "Pro") : .notInstalled,
                usage: capturedAt.map {
                    ProviderUsageSnapshot(
                        shortWindow: WindowUsage(label: "x", utilization: 1, resetsAt: now, windowDuration: 1),
                        longWindow: nil, planLabel: "Pro", extraUsage: nil, creditsBalance: nil, capturedAt: $0)
                },
                error: nil, lastSynced: nil, isLoading: false)
        }
        let t = now
        XCTAssertFalse(UsageViewModel.bridgeStateDiffers(state(t), state(t)), "identical re-read must not reload widgets")
        XCTAssertTrue(UsageViewModel.bridgeStateDiffers(state(t), state(t.addingTimeInterval(60))))
        XCTAssertTrue(UsageViewModel.bridgeStateDiffers(state(nil, connected: false), state(t)))
        XCTAssertTrue(UsageViewModel.bridgeStateDiffers(state(t), state(nil, connected: false)))
    }

    // MARK: - Model compatibility

    func testUsageSnapshot_decodesJSONWrittenBeforeCapturedAtExisted() throws {
        let json = """
        {"shortWindow":{"label":"5-Hour","utilization":10,"resetsAt":0,"windowDuration":18000},
         "planLabel":"Max"}
        """.data(using: .utf8)!
        let snap = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: json)
        XCTAssertNil(snap.capturedAt)
        XCTAssertNil(snap.estimated)
    }

    // MARK: - Demo mode

    func testDemoData_coversEveryWebPool() {
        for id in WebCompanionProvider.webOnlyPools {
            XCTAssertNotNil(DemoData.allSnapshots[id], "\(id) missing from demo data")
        }
    }
}
