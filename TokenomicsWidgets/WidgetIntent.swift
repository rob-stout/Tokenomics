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

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    // These strings MUST equal the matching ProviderId.poolLabel (asserted in
    // PoolLabelAlignmentTests). "Best of All (Smart)" is the only non-pool entry.
    static var caseDisplayRepresentations: [WidgetProviderSelection: DisplayRepresentation] = [
        .smart:           "Best of All (Smart)",
        .claude:          "Anthropic",
        .chatgpt:         "ChatGPT",
        .codex:           "Codex CLI",
        .geminiConsumer:  "Gemini (app)",
        .gemini:          "Gemini CLI",
        .copilot:         "GitHub Copilot",
        .cursor:          "Cursor",
        .elevenlabs:      "ElevenLabs",
        .runway:          "Runway",
        .stableDiffusion: "Stability AI"
    ]
}

#if WIDGET_EXTENSION
/// Configurable intent for the small widget — lets users pick a specific provider or Smart mode
struct SelectProviderIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Provider"
    static var description = IntentDescription("Choose which AI provider to show, or use Smart mode to show the most critical one.")

    @Parameter(title: "Provider", default: .smart)
    var provider: WidgetProviderSelection
}
#endif
