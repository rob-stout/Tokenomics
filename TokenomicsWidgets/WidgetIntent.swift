import AppIntents
import WidgetKit

/// Which provider to display in the small widget
enum WidgetProviderSelection: String, AppEnum {
    case smart = "smart"
    case claude = "claude"
    case copilot = "copilot"
    case cursor = "cursor"
    case codex = "codex"
    case gemini = "gemini"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    static var caseDisplayRepresentations: [WidgetProviderSelection: DisplayRepresentation] = [
        .smart: "Best of All (Smart)",
        .claude: "Claude Code",
        .copilot: "GitHub Copilot",
        .cursor: "Cursor",
        .codex: "Codex CLI",
        .gemini: "Gemini CLI"
    ]
}

/// Configurable intent for the small widget — lets users pick a specific provider or Smart mode
struct SelectProviderIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Provider"
    static var description = IntentDescription("Choose which AI provider to show, or use Smart mode to show the most critical one.")

    @Parameter(title: "Provider", default: .smart)
    var provider: WidgetProviderSelection
}
