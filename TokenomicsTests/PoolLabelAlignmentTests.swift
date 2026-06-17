import XCTest
import AppIntents
@testable import Tokenomics

/// Keeps the per-pool label aligned across every surface that shows it:
/// the Connections toggles, usage notifications, the popover pool headers, and
/// the widget. `ProviderId.poolLabel` is the single source of truth; this file
/// asserts the surfaces that *resolve* a label all resolve to it, so the label
/// can't quietly diverge again.
///
/// (Toggles and popover headers call `provider.poolLabel` directly — there's no
/// indirection to test there; the pinned values below guard them. Notification
/// and the widget bake go through code that this file exercises against the SoT.)
final class PoolLabelAlignmentTests: XCTestCase {

    // MARK: - Source of truth: pinned values

    /// Snapshot of every pool's label. If a label intentionally changes, update
    /// this map — and every surface updates with it because they all read
    /// `poolLabel`. If it changes by accident, this fails loudly.
    func testPoolLabel_pinnedValues() {
        let expected: [ProviderId: String] = [
            .claude: "Anthropic",
            .chatgpt: "ChatGPT",
            .codex: "Codex CLI",
            .geminiConsumer: "Gemini (app)",
            .gemini: "Gemini CLI",
            .copilot: "GitHub Copilot",
            .cursor: "Cursor",
            .stableDiffusion: "Stability AI",
            .midjourney: "Midjourney",
            .leonardo: "Leonardo",
            .runway: "Runway",
            .elevenlabs: "ElevenLabs",
            .suno: "Suno",
            .udio: "Udio",
            .grok: "Grok",
            .perplexity: "Perplexity",
        ]
        for id in ProviderId.allCases {
            XCTAssertEqual(id.poolLabel, expected[id],
                           "poolLabel changed for \(id.rawValue) — update the pin AND verify every surface.")
        }
    }

    /// Multi-pool brands MUST disambiguate by pool — that's the whole point.
    /// displayName is brand-ish and collides, so it must differ from poolLabel
    /// here. This guards against someone "simplifying" a surface back to displayName.
    func testMultiPoolBrands_poolLabelDiffersFromDisplayName() {
        for id in [ProviderId.codex, .gemini, .geminiConsumer] {
            XCTAssertNotEqual(id.poolLabel, id.displayName,
                              "\(id.rawValue): poolLabel must differ from the brand-ish displayName.")
        }
    }

    // MARK: - Notification surface uses the SoT

    func testNotificationTitle_usesPoolLabelForEveryProvider() {
        for id in ProviderId.allCases {
            XCTAssertEqual(
                NotificationService.usageAlertTitle(for: id, utilization: 50),
                "\(id.poolLabel) at 50%"
            )
        }
    }

    // MARK: - Widget bake uses the SoT

    func testWidgetSnapshotBake_usesPoolLabelForEveryProvider() {
        let providers = ProviderId.allCases.map { ($0, Self.sampleSnapshot()) }
        let entries = WidgetDataStore.makeEntries(providers: providers)

        XCTAssertEqual(entries.count, ProviderId.allCases.count)
        for (id, entry) in zip(ProviderId.allCases, entries) {
            XCTAssertEqual(entry.id, id.rawValue)
            XCTAssertEqual(entry.displayName, id.poolLabel,
                           "Widget snapshot baked the wrong label for \(id.rawValue) — must be poolLabel.")
            // Icon + surface are baked from the SoT too — guards the "?" drift
            // (widget's own icon map had omitted chatgpt / geminiConsumer).
            XCTAssertEqual(entry.iconBaseName, id.iconBaseName,
                           "Widget snapshot baked the wrong icon for \(id.rawValue).")
            XCTAssertEqual(entry.surfaceSymbol, id.surfaceSymbol,
                           "Widget snapshot baked the wrong surface glyph for \(id.rawValue).")
        }
    }

    /// The icon-map drift that rendered ChatGPT / Gemini-app as "?": both pools of
    /// a multi-pool brand must bake a real icon base name (never nil/empty).
    func testMultiPoolWebPools_bakeARealIconBaseName() {
        for id in [ProviderId.chatgpt, .geminiConsumer] {
            XCTAssertFalse(id.iconBaseName.isEmpty)
            XCTAssertEqual(id.surfaceSymbol, "puzzlepiece.extension")
        }
    }

    // MARK: - Small-widget picker uses the SoT

    /// The small-widget provider picker (App Intents AppEnum) must label each
    /// pool the same as its toggle — i.e. `poolLabel`. Guards against the picker
    /// drifting back to brand-ish names ("OpenAI", "Google AI", "Stable Diffusion").
    func testWidgetPickerLabels_matchPoolLabel() {
        let mapping: [(WidgetProviderSelection, ProviderId)] = [
            (.claude, .claude),
            (.chatgpt, .chatgpt),
            (.codex, .codex),
            (.geminiConsumer, .geminiConsumer),
            (.gemini, .gemini),
            (.copilot, .copilot),
            (.cursor, .cursor),
            (.elevenlabs, .elevenlabs),
            (.runway, .runway),
            (.stableDiffusion, .stableDiffusion),
            (.midjourney, .midjourney),
            (.leonardo, .leonardo),
            (.grok, .grok),
            (.perplexity, .perplexity),
        ]
        for (pick, provider) in mapping {
            let rep = WidgetProviderSelection.caseDisplayRepresentations[pick]
            let label = rep.map { String(localized: $0.title) }
            XCTAssertEqual(label, provider.poolLabel,
                           "Widget picker label for \(pick.rawValue) must equal poolLabel.")
        }
    }

    // MARK: - Fixture

    private static func sampleSnapshot() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "5-Hour Window",
                utilization: 50,
                resetsAt: Date().addingTimeInterval(3600),
                windowDuration: 5 * 3600
            ),
            longWindow: nil,
            planLabel: "Pro",
            extraUsage: nil,
            creditsBalance: nil
        )
    }
}
