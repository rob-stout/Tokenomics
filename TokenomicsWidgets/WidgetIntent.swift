import AppKit
import AppIntents
import WidgetKit

/// Which provider to display in the small widget.
///
/// Raw values are the stable on-disk identity — never rename an existing case's
/// raw value or users' saved widget configurations will silently resolve to nil.
///
/// Labels mirror `ProviderId.poolLabel` — the source of truth the Connections
/// toggles, popover, notifications, and widget all use — so the picker reads the
/// same as everywhere else. One entry per pool (no brand-vs-pool duplicates).
/// Case-declaration order is the picker order: grouped by brand to match the
/// Connections list. Enforced by `PoolLabelAlignmentTests`.
///
/// Removed in this pass: the legacy `.codexCLI` / `.geminiCLI` aliases (they
/// duplicated `.codex` / `.gemini`). Any saved config referencing those raw
/// values resolves to the default (Smart) — same data was reachable via the
/// relabeled `.codex` / `.gemini` entries.
enum WidgetProviderSelection: String, AppEnum {
    // Raw values are frozen — do not rename.
    case smart           = "smart"
    case claude          = "claude"
    case chatgpt         = "chatgpt"
    case codex           = "codex"            // Codex CLI data
    case geminiConsumer  = "geminiConsumer"   // Gemini (app) data
    case gemini          = "gemini"           // Gemini CLI data
    case copilot         = "copilot"
    case cursor          = "cursor"
    case elevenlabs      = "elevenlabs"
    case runway          = "runway"
    case stableDiffusion = "stableDiffusion"
    // Web-companion pools (NMH bridge). Raw values match ProviderId.
    case midjourney      = "midjourney"
    case leonardo        = "leonardo"
    case grok            = "grok"
    case perplexity      = "perplexity"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    // These strings MUST equal the matching ProviderId.poolLabel (asserted in
    // PoolLabelAlignmentTests). "Best of All (Smart)" is the only non-pool entry.
    static let caseDisplayRepresentations: [WidgetProviderSelection: DisplayRepresentation] = [
        .smart:           "Best of All (Smart)",
        .claude:          "Claude",
        .chatgpt:         "ChatGPT",
        .codex:           "Codex CLI",
        .geminiConsumer:  "Gemini (app)",
        .gemini:          "Gemini CLI",
        .copilot:         "GitHub Copilot",
        .cursor:          "Cursor",
        .elevenlabs:      "ElevenLabs",
        .runway:          "Runway",
        .stableDiffusion: "Stability AI",
        .midjourney:      "Midjourney",
        .leonardo:        "Leonardo",
        .grok:            "Grok",
        .perplexity:      "Perplexity"
    ]
}

#if WIDGET_EXTENSION
/// Configurable intent for the small widget — lets users pick a specific provider or Smart mode
struct SelectProviderIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Provider"
    static let description = IntentDescription("Choose which AI provider to show, or use Smart mode to show the most critical one.")

    @Parameter(title: "Provider", default: .smart)
    var provider: WidgetProviderSelection
}
#endif

#if WIDGET_EXTENSION
/// Widget refresh button. A widget can't fetch usage itself, so this asks the
/// app to poll via `tokenomics://refresh`, which also launches the app when it
/// isn't running. Opened in the background so a tap never pulls focus.
///
/// Widget-extension only: if the app target also contained this intent, the
/// system could run it in the app's process instead, which is slower and
/// brings the app forward.
struct WidgetRefreshIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Widget"
    static let isDiscoverable = false

    /// Which widget size was tapped, so only that widget's arrow turns.
    @Parameter(title: "Widget")
    var widget: String

    init() {}

    init(widget: String) {
        self.widget = widget
    }

    func perform() async throws -> some IntentResult {
        WidgetRefreshTaps.increment(widget)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        // Fire and forget. WidgetKit redraws (and the arrow turns) only once
        // perform() returns, so waiting for the app to receive the URL —
        // or to launch — showed up as lag between the tap and the turn.
        NSWorkspace.shared.open(URL(string: "tokenomics://refresh")!, configuration: configuration, completionHandler: nil)
        return .result()
    }
}

/// Tap counters in the App Group container, read into each timeline entry.
///
/// Kept per widget size: with one shared count, a widget that hadn't redrawn
/// since the others were tapped jumped several taps at once and spun that
/// many turns. Counts only go up, so every tap is a new value to turn to.
enum WidgetRefreshTaps {
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetDataStore.appGroupId)?
            .appendingPathComponent("widget-refresh-taps.json")
    }

    static var all: [String: Int] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    static func increment(_ widget: String) {
        guard let fileURL else { return }
        var taps = all
        taps[widget, default: 0] += 1
        try? JSONEncoder().encode(taps).write(to: fileURL, options: .atomic)
    }
}
#endif
