import XCTest
import SwiftUI
import AppKit
@testable import Tokenomics

/// Renders the popover with every web pool fed from a fixture `ext-side.json` state, and
/// writes the widget payload a real run would produce — so a human (or the widget
/// harness) can look at the result. Skipped unless `WEBPOOLS_SHOT_DIR` is set:
///
///     TEST_RUNNER_WEBPOOLS_SHOT_DIR=/some/dir xcodebuild test -only-testing:TokenomicsTests/WebPoolsVisualTests …
///
/// Never touches the real App Group: widget data goes to a scratch file via
/// `applyDemoData(widgetStoreURL:)`.
@MainActor
final class WebPoolsVisualTests: XCTestCase {

    private let now = Date()

    private func bridge(
        _ id: ProviderId, plan: String, age: TimeInterval = 120, estimated: Bool = false,
        short: (String, Double, TimeInterval, TimeInterval, String?),
        long: (String, Double, TimeInterval, TimeInterval, String?)? = nil
    ) -> BridgeSnapshot {
        func w(_ t: (String, Double, TimeInterval, TimeInterval, String?)) -> BridgeWindow {
            BridgeWindow(label: t.0, utilization: t.1, resetsAt: now.addingTimeInterval(t.2),
                         windowDurationSec: t.3, sublabelOverride: t.4)
        }
        return BridgeSnapshot(provider: id.rawValue, capturedAt: now.addingTimeInterval(-age),
                              estimated: estimated, shortWindow: w(short), longWindow: long.map(w), planLabel: plan)
    }

    /// The fixture `ext-side.json` content: every web pool, two of them stale.
    private var extState: ExtSideState {
        let h: TimeInterval = 3600, d: TimeInterval = 86_400
        let snaps: [BridgeSnapshot] = [
            bridge(.chatgpt, plan: "Plus", age: 2 * h, estimated: true,
                   short: ("5-Hour", 0.25, 3 * h, 5 * h, nil), long: ("Weekly", 0.5, 4 * d, 7 * d, nil)),
            bridge(.geminiConsumer, plan: "Gemini",
                   short: ("5-Hour", 0.12, 4 * h, 5 * h, nil), long: ("Weekly", 0.31, 5 * d, 7 * d, nil)),
            bridge(.midjourney, plan: "Standard", age: 3 * h,
                   short: ("Fast Hours", 0.64, 12 * d, 30 * d, "6.4 of 15 hrs used")),
            bridge(.grok, plan: "Free", short: ("Daily", 0.8, 20 * h, d, nil)),
            bridge(.perplexity, plan: "Pro", short: ("Daily", 0.15, 20 * h, d, nil)),
            bridge(.leonardo, plan: "Apprentice", short: ("Tokens", 0.62, 9 * d, 30 * d, "1,140 tokens left")),
            bridge(.suno, plan: "Pro", age: 60, short: ("Credits", 0.4, 12 * d, 30 * d, "1,500 credits left")),
            bridge(.udio, plan: "Free", short: ("Monthly", 0.01, 30 * d, 30 * d, nil),
                   long: ("Daily", 0.2, d, d, nil)),
        ]
        return ExtSideState(updatedAt: now,
                            snapshots: Dictionary(uniqueKeysWithValues: snaps.map { ($0.provider, $0) }),
                            providerVisibility: [:])
    }

    /// Fixture state → the same provider code path production uses → view model.
    private func makeViewModel(widgetFile: URL) async throws -> UsageViewModel {
        let state = extState
        var snapshots = DemoData.allSnapshots.filter { [.claude, .codex, .gemini, .copilot].contains($0.key) }
        for id in WebCompanionProvider.webOnlyPools {
            let provider = WebCompanionProvider(id: id, snapshotReader: { state.snapshots[id.rawValue] }, now: { [now] in now })
            snapshots[id] = try await provider.fetchUsage()
        }
        let vm = UsageViewModel()
        vm.applyDemoData(snapshots: snapshots, widgetStoreURL: widgetFile)
        return vm
    }

    private func render<V: View>(_ view: V, to url: URL) async throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // The bars and percentages animate in on appear; let that finish before capturing.
        try await Task.sleep(for: .seconds(2))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return XCTFail("no bitmap rep")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    func testRenderPopoverAndWidgetPayload() async throws {
        guard let dir = ProcessInfo.processInfo.environment["WEBPOOLS_SHOT_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_WEBPOOLS_SHOT_DIR to render")
        }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let widgetFile = out.appendingPathComponent("widget-data-brand-off.json")
        let defaults = UserDefaults.standard
        let priorFlag = defaults.object(forKey: FeatureFlags.brandAggregationKey)
        let priorOrder = SettingsService.providerOrder
        let priorOrderStamp = defaults.object(forKey: "providerOrderChangedAt")
        let priorTab = SettingsService.selectedTab
        defer {
            // The view model persists order/tab as it's mutated; leave no trace for other tests.
            SettingsService.providerOrder = priorOrder
            // Restore the sync stamp too, or the test order looks like a fresh user
            // reorder and gets pushed to the extension.
            if let priorOrderStamp { defaults.set(priorOrderStamp, forKey: "providerOrderChangedAt") }
            else { defaults.removeObject(forKey: "providerOrderChangedAt") }
            SettingsService.selectedTab = priorTab
            if let priorFlag { defaults.set(priorFlag, forKey: FeatureFlags.brandAggregationKey) }
            else { defaults.removeObject(forKey: FeatureFlags.brandAggregationKey) }
        }

        let updater = UpdaterService()

        // Brand-aggregation ON: one tab per brand, pools stacked inside.
        defaults.set(true, forKey: FeatureFlags.brandAggregationKey)
        for (name, first) in [("openai", ProviderId.chatgpt), ("google", .geminiConsumer),
                              ("midjourney", .midjourney), ("suno", .suno), ("udio", .udio)] {
            let vm = try await makeViewModel(widgetFile: widgetFile)
            vm.providerOrder = [first] + ProviderId.allCases.filter { $0 != first }
            vm.selectedTab = first
            try await render(PopoverView(viewModel: vm, updaterService: updater)
                .background(Color(nsColor: .windowBackgroundColor)),
                       to: out.appendingPathComponent("popover-brand-\(name).png"))
        }

        // Brand-aggregation OFF (legacy: one tab per ProviderId) — also writes the
        // widget payload for the widget renderer, once per flag value.
        defaults.set(false, forKey: FeatureFlags.brandAggregationKey)
        let vm = try await makeViewModel(widgetFile: widgetFile)
        vm.providerOrder = [.chatgpt] + ProviderId.allCases.filter { $0 != .chatgpt }
        vm.selectedTab = .chatgpt
        try await render(PopoverView(viewModel: vm, updaterService: updater)
            .background(Color(nsColor: .windowBackgroundColor)),
                   to: out.appendingPathComponent("popover-legacy-chatgpt.png"))

        defaults.set(true, forKey: FeatureFlags.brandAggregationKey)
        _ = try await makeViewModel(widgetFile: out.appendingPathComponent("widget-data-brand-on.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: widgetFile.path))
    }
}
