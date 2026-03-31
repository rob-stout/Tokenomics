import AppIntents
import WidgetKit

/// Which provider to display in the widget
enum WidgetProviderSelection: String, AppEnum {
    case smart           = "smart"
    case claude          = "claude"
    case copilot         = "copilot"
    case cursor          = "cursor"
    case codex           = "codex"
    case gemini          = "gemini"
    case elevenlabs      = "elevenlabs"
    case runway          = "runway"
    case stableDiffusion = "stableDiffusion"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    static var caseDisplayRepresentations: [WidgetProviderSelection: DisplayRepresentation] = [
        .smart:           "Best of All (Smart)",
        .claude:          "Claude Code",
        .copilot:         "GitHub Copilot",
        .cursor:          "Cursor",
        .codex:           "OpenAI",
        .gemini:          "Google AI",
        .elevenlabs:      "ElevenLabs",
        .runway:          "Runway",
        .stableDiffusion: "Stable Diffusion"
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
