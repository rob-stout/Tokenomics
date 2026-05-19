import AppIntents
import WidgetKit

/// Which provider to display in the small widget.
///
/// Raw values are the stable on-disk identity — never rename an existing case's
/// raw value or users' saved widget configurations will silently resolve to nil.
///
/// Downgrade-safety contract:
///   .codex   raw "codex"   → OpenAI / Codex CLI data   (was always Codex CLI)
///   .gemini  raw "gemini"  → Google AI / Gemini CLI data (was always Gemini CLI)
///
/// Phase 5.6.C additive cases (new raw values, no existing value touched):
///   .chatgpt    → resolves to ProviderId .chatgpt (consumer ChatGPT data via NMH)
///   .codexCLI   → resolves to ProviderId .codex   (same data as existing .codex)
///   .geminiCLI  → resolves to ProviderId .gemini  (same data as existing .gemini)
///
/// Users who already have "OpenAI" or "Google AI" selected keep those choices
/// working unchanged — the new per-pool entries are presented alongside them
/// so users can switch if they want explicit labeling.
enum WidgetProviderSelection: String, AppEnum {
    // MARK: Existing cases — raw values are frozen; do not rename
    case smart           = "smart"
    case claude          = "claude"
    case copilot         = "copilot"
    case cursor          = "cursor"
    case codex           = "codex"
    case gemini          = "gemini"
    case elevenlabs      = "elevenlabs"
    case runway          = "runway"
    case stableDiffusion = "stableDiffusion"

    // MARK: Phase 5.6.C additions — new raw values only, no existing value touched
    /// Consumer ChatGPT usage (chat sessions via NMH bridge).
    case chatgpt    = "chatgpt"
    /// Codex CLI usage — same data source as the existing .codex case,
    /// surfaced as an explicit per-pool entry for clarity.
    case codexCLI   = "codexCLI"
    /// Gemini CLI usage — same data source as the existing .gemini case,
    /// surfaced as an explicit per-pool entry for clarity.
    case geminiCLI  = "geminiCLI"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    static var caseDisplayRepresentations: [WidgetProviderSelection: DisplayRepresentation] = [
        // Existing entries — display strings intentionally unchanged
        .smart:           "Best of All (Smart)",
        .claude:          "Claude Code",
        .copilot:         "GitHub Copilot",
        .cursor:          "Cursor",
        .codex:           "OpenAI",
        .gemini:          "Google AI",
        .elevenlabs:      "ElevenLabs",
        .runway:          "Runway",
        .stableDiffusion: "Stable Diffusion",
        // Phase 5.6.C additions
        .chatgpt:         "ChatGPT",
        .codexCLI:        "Codex CLI",
        .geminiCLI:       "Gemini CLI"
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
