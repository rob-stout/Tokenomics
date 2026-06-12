import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - Provider Identity

/// Supported AI providers across coding, image, video, and audio categories
enum ProviderId: String, CaseIterable, Codable, Sendable, Identifiable {
    // Platforms (shared billing pools)
    case claude
    case codex
    case gemini
    // Consumer web-companion sources (browser-session data via NMH bridge)
    case chatgpt
    case geminiConsumer
    // Coding Tools
    case copilot
    case cursor
    // Image Generation
    case stableDiffusion
    case midjourney
    case leonardo
    // Video Generation
    case runway
    // Music / Audio / Voice
    case elevenlabs
    case suno
    case udio
    // AI Assistants / Search
    case grok
    case perplexity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Anthropic"
        case .chatgpt: return "ChatGPT"
        case .geminiConsumer: return "Gemini"
        case .copilot: return "GitHub Copilot"
        case .cursor: return "Cursor"
        case .codex: return "OpenAI"
        case .gemini: return "Google AI"
        case .stableDiffusion: return "Stability AI"
        case .midjourney: return "Midjourney"
        case .leonardo: return "Leonardo"
        case .runway: return "Runway"
        case .elevenlabs: return "ElevenLabs"
        case .suno: return "Suno"
        case .udio: return "Udio"
        case .grok: return "Grok"
        case .perplexity: return "Perplexity"
        }
    }

    /// Shorter name for tab bars where horizontal space is limited
    var tabLabel: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .geminiConsumer: return "Gemini"
        case .copilot: return "Copilot"
        case .cursor: return "Cursor"
        case .codex: return "OpenAI"
        case .gemini: return "Google AI"
        case .stableDiffusion: return "Stability"
        case .midjourney: return "Midjourney"
        case .leonardo: return "Leonardo"
        case .runway: return "Runway"
        case .elevenlabs: return "ElevenLabs"
        case .suno: return "Suno"
        case .udio: return "Udio"
        case .grok: return "Grok"
        case .perplexity: return "Perplexity"
        }
    }

    /// Short label for menu bar and tab icons.
    /// Most providers use a single letter; ChatGPT uses the full string because
    /// all single letters are already claimed by other providers.
    var shortLabel: String {
        switch self {
        case .claude: return "C"
        case .chatgpt: return "ChatGPT"
        // geminiConsumer uses "Gw" (Gemini web) to distinguish from the CLI "G".
        // Both pools are separately-pinnable in the menu bar; distinct labels
        // keep the rings identifiable when both are pinned simultaneously.
        case .geminiConsumer: return "Gw"
        case .copilot: return "P"
        case .cursor: return "U"
        case .codex: return "X"
        case .gemini: return "G"
        case .stableDiffusion: return "S"
        case .midjourney: return "M"
        case .leonardo: return "L"
        case .runway: return "R"
        case .elevenlabs: return "E"
        case .suno: return "N"
        case .udio: return "D"
        case .grok: return "K"
        case .perplexity: return "Q"
        }
    }

    /// Terminal command to authenticate (CLI-based providers only)
    var loginCommand: String {
        switch self {
        case .claude: return "claude"
        case .copilot: return "gh auth login"
        case .cursor: return "open -a Cursor"
        case .codex: return "codex login"
        case .gemini: return "gemini login"
        // Browser-session and API-key providers have no CLI auth
        case .chatgpt, .geminiConsumer, .stableDiffusion, .midjourney, .leonardo,
             .runway, .elevenlabs, .suno, .udio, .grok, .perplexity: return ""
        }
    }

    /// Whether this provider exposes rate-limit / usage data
    var supportsUsageTracking: Bool {
        switch self {
        case .claude, .copilot, .cursor, .codex, .gemini: return true
        case .elevenlabs, .runway, .stableDiffusion: return true
        // chatgpt and geminiConsumer data arrives via the NMH bridge (browser-session)
        case .chatgpt, .geminiConsumer: return true
        // Web-companion readers via NMH bridge
        case .midjourney, .grok, .perplexity, .leonardo: return true
        // When flipping any of these to `true`, update docs/PRIVACY.md —
        // the placeholder note currently tells users Tokenomics makes no
        // network calls or credential reads for these providers.
        case .suno, .udio: return false
        }
    }

    /// Whether this provider uses a Personal Access Token instead of CLI-based auth
    var usesPATAuth: Bool {
        // All providers now have zero-friction auth or API key auth
        return false
    }

    /// Whether auth is handled automatically by the provider's own app (no CLI/PAT needed)
    var hasAutoAuth: Bool {
        switch self {
        case .cursor: return true
        default: return false
        }
    }

    /// Install command for CLI-based providers
    var installCommand: String {
        switch self {
        case .claude: return "npm install -g @anthropic-ai/claude-code"
        case .copilot: return "brew install gh"
        case .cursor: return "brew install --cask cursor"
        case .codex: return "npm install -g @openai/codex"
        case .gemini: return "npm install -g @google/gemini-cli"
        // Browser-session and API-key providers don't need installation
        case .chatgpt, .geminiConsumer, .stableDiffusion, .midjourney, .leonardo,
             .runway, .elevenlabs, .suno, .udio, .grok, .perplexity: return ""
        }
    }


}

// MARK: - Provider Categories

extension ProviderId {

    /// Groups providers into sections for the Connections page
    enum ProviderCategory: String, CaseIterable {
        case platforms       = "PLATFORMS"
        case codingTools     = "CODING TOOLS"
        case imageGeneration = "IMAGE GENERATION"
        case videoGeneration = "VIDEO GENERATION"
        case musicAudioVoice = "MUSIC / AUDIO / VOICE"
        case aiAssistants    = "AI ASSISTANTS"
    }

    var category: ProviderCategory {
        switch self {
        case .claude, .chatgpt, .geminiConsumer, .stableDiffusion: return .platforms
        case .copilot, .cursor, .codex, .gemini: return .codingTools
        case .midjourney, .leonardo: return .imageGeneration
        case .runway: return .videoGeneration
        case .elevenlabs, .suno, .udio: return .musicAudioVoice
        case .grok, .perplexity: return .aiAssistants
        }
    }

    /// Whether this provider has a working data integration (false = "Coming Soon").
    /// chatgpt data arrives via the NMH bridge, not a direct API, so it counts as true.
    var hasAPI: Bool {
        // geminiConsumer data comes via the NMH bridge — counts as "has API"
        // for the purposes of showing the setup CTA in the chooser.
        switch self {
        case .suno, .udio: return false
        default: return true
        }
    }

    /// Subtitle clarifying what this row actually tracks. Anthropic's row covers the
    /// full subscription pool; Codex/Gemini rows are scoped to their CLI tool only
    /// (chat/image/video usage on those platforms is a separate quota with no public
    /// read API).
    var scopeDescription: String? {
        switch self {
        case .claude: return "Claude Chat · Cowork · Code"
        case .chatgpt: return "ChatGPT · via browser session"
        case .geminiConsumer: return "Gemini · via browser session"
        case .codex: return "Codex CLI"
        case .gemini: return "Gemini CLI"
        case .stableDiffusion: return "Stable Diffusion · Stable Image · Stable Video"
        case .grok: return "Grok · via browser session"
        case .perplexity: return "Perplexity · via browser session"
        case .leonardo: return "Leonardo · via browser session"
        default: return nil
        }
    }

    /// Anchor fragment that deep-links to the matching section of trytokenomics.com/setup.html
    var setupGuideAnchor: String {
        switch self {
        case .claude: return "#anthropic"
        case .chatgpt: return "#chatgpt"
        case .geminiConsumer: return "#google"
        case .codex: return "#openai"
        case .gemini: return "#google"
        case .copilot: return "#copilot"
        case .cursor: return "#cursor"
        case .stableDiffusion, .runway, .elevenlabs: return "#api-key"
        case .midjourney, .grok, .perplexity, .leonardo: return "#browser-extension"
        case .suno, .udio: return ""
        }
    }

    /// Whether this provider authenticates via an API key stored in Keychain
    var usesAPIKeyAuth: Bool {
        switch self {
        // elevenlabs now uses Firebase bearer auth (content-script-delivered),
        // not a Keychain API key — this flag gates APIKeyConnector which is
        // no longer the right connector for it. Keep false here to avoid routing
        // it to the old API-key flow. The connector factory handles it via
        // BrowserExtensionConnector or a future ElevenLabsConnector.
        case .runway, .stableDiffusion: return true
        default: return false
        }
    }

    /// THE per-pool label — the single source of truth for how a pool is named
    /// to the user. Every surface that shows a pool must use this and only this:
    /// the Connections toggles, usage notifications, the popover pool section
    /// headers, the widget (baked into the snapshot by `WidgetDataStore.write`),
    /// the Pin Tracker, and the display-mode menu.
    ///
    /// It is tool-specific so multi-pool brands disambiguate: "Codex CLI" vs
    /// "ChatGPT" (both OpenAI), "Gemini CLI" vs "Gemini (app)" (both Google).
    /// Do NOT use `displayName` for pool labels — that is brand-ish ("OpenAI",
    /// "Google AI") and collides across a brand's pools. See `PoolLabelAlignmentTests`.
    var poolLabel: String {
        switch self {
        case .claude:          return "Anthropic"
        case .chatgpt:         return "ChatGPT"
        case .geminiConsumer:  return "Gemini (app)"
        case .codex:           return "Codex CLI"
        case .gemini:          return "Gemini CLI"
        case .copilot:         return "GitHub Copilot"
        case .cursor:          return "Cursor"
        case .stableDiffusion: return "Stability AI"
        case .midjourney:      return "Midjourney"
        case .leonardo:        return "Leonardo"
        case .runway:          return "Runway"
        case .elevenlabs:      return "ElevenLabs"
        case .suno:            return "Suno"
        case .udio:            return "Udio"
        case .grok:            return "Grok"
        case .perplexity:      return "Perplexity"
        }
    }

    /// Base name for icon assets (without the -white/-black/-d.blue suffix).
    /// Maps enum rawValues to actual file names in Provider Icons/.
    var iconBaseName: String {
        switch self {
        case .claude: return "Claude"
        // ChatGPT has no dedicated asset; the "Codex" set IS the OpenAI mark,
        // which is the correct logo for both OpenAI pools (ChatGPT + Codex).
        case .chatgpt: return "Codex"
        // geminiConsumer reuses the same Gemini icon assets — same brand, separate pool.
        case .geminiConsumer: return "Gemini"
        case .codex: return "Codex"
        case .copilot: return "Copilot"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini"
        case .stableDiffusion: return "stability"
        case .midjourney: return "midjourney"
        // Icon assets (black/d.blue/white, SVG + PNG 1x/2x) exist for all three
        // in Tokenomics/Resources/Provider Icons/.
        case .leonardo: return "leonardo"
        case .runway: return "runway"
        case .elevenlabs: return "elevenlabs"
        case .suno: return "suno"
        case .udio: return "udio"
        case .grok: return "grok"
        case .perplexity: return "perplexity"
        }
    }
}

// MARK: - Brand Identity

/// A user-facing brand grouping. Several `ProviderId`s can belong to one brand
/// when they share an account but track separate usage meters per surface
/// (e.g. OpenAI's ChatGPT consumer chat and Codex CLI are one brand, two
/// pools). Anthropic is the only case where the account itself returns one
/// unified set of windows — the brand still maps to a set, just a single-pool
/// one.
///
/// Used by:
/// - `MultiSelectStep` rows (brand-level)
/// - Popover tabs (brand-level) with per-pool sub-sections inside
/// - Pin Tracker dropdown (per-pool entries, derived from the brand map)
/// - Medium/large widgets (brand parent row + per-pool sub-rows)
///
/// Small widgets stay at the ProviderId layer (they pick one pool at a time
/// via an additive enum, no brand grouping needed).
enum BrandId: String, CaseIterable, Codable, Sendable, Identifiable {
    case anthropic
    case openai
    case google
    case copilot
    case cursor
    case stability
    case midjourney
    case leonardo
    case runway
    case elevenlabs
    case suno
    case udio
    case grok
    case perplexity

    var id: String { rawValue }

    /// Human-readable name shown in tabs, settings, and the multi-select.
    var displayName: String {
        switch self {
        case .anthropic:  return "Claude"
        case .openai:     return "ChatGPT"
        case .google:     return "Gemini"
        case .copilot:    return "GitHub Copilot"
        case .cursor:     return "Cursor"
        case .stability:  return "Stability AI"
        case .midjourney: return "Midjourney"
        case .leonardo:   return "Leonardo"
        case .runway:     return "Runway"
        case .elevenlabs: return "ElevenLabs"
        case .suno:       return "Suno"
        case .udio:       return "Udio"
        case .grok:       return "Grok"
        case .perplexity: return "Perplexity"
        }
    }

    /// Corporate attribution shown as row sub-text. nil when the brand name
    /// already encodes the company (e.g. "Cursor", "Runway").
    var companyAttribution: String? {
        switch self {
        case .anthropic:  return "Anthropic"
        case .openai:     return "OpenAI"
        case .google:     return "Google"
        case .grok:       return "xAI"
        case .perplexity: return "Perplexity AI"
        case .leonardo:   return "Leonardo.Ai"
        default:          return nil
        }
    }

    /// The set of `ProviderId`s that contribute usage data to this brand.
    /// A brand with multiple ProviderIds is a "multi-pool" brand — its UI
    /// surfaces (popover tab body, widget block) render one section per
    /// ProviderId stacked beneath the brand header.
    ///
    /// Single-pool brands return a one-element set; the rendering layer can
    /// treat them uniformly with multi-pool brands without special-casing.
    var pools: Set<ProviderId> {
        switch self {
        case .anthropic:  return [.claude]
        case .openai:     return [.chatgpt, .codex]
        // Google brand: CLI pool (.gemini) + consumer web-app pool (.geminiConsumer)
        case .google:     return [.gemini, .geminiConsumer]
        case .copilot:    return [.copilot]
        case .cursor:     return [.cursor]
        case .stability:  return [.stableDiffusion]
        case .midjourney: return [.midjourney]
        case .leonardo:   return [.leonardo]
        case .runway:     return [.runway]
        case .elevenlabs: return [.elevenlabs]
        case .suno:       return [.suno]
        case .udio:       return [.udio]
        case .grok:       return [.grok]
        case .perplexity: return [.perplexity]
        }
    }
}

extension ProviderId {
    /// How this pool's usage is read — drives a small corner badge on the
    /// provider icon so visually-identical sub-pools (e.g. ChatGPT vs Codex,
    /// both the OpenAI mark) are distinguishable at a glance.
    enum TrackingSurface {
        case browserExtension   // read via the browser extension / web session
        case cli                // read from a local coding tool's files
        case apiKey             // read via a user-supplied API key
    }

    var trackingSurface: TrackingSurface {
        switch self {
        case .chatgpt, .geminiConsumer, .midjourney, .grok, .perplexity, .leonardo, .suno, .udio:
            return .browserExtension
        case .claude, .codex, .gemini, .cursor, .copilot:
            return .cli
        case .elevenlabs, .runway, .stableDiffusion:
            return .apiKey
        }
    }

    /// SF Symbol representing this pool's surface (browser extension vs CLI).
    /// Used as the icon for nested sub-pool rows, where the brand mark already
    /// lives on the group header — so the surface glyph distinguishes the pools.
    /// nil for API-key pools (none are multi-pool today).
    var surfaceSymbol: String? {
        switch trackingSurface {
        case .browserExtension: return "puzzlepiece.extension"
        case .cli:              return "terminal"
        case .apiKey:           return nil
        }
    }
}

extension BrandId {
    /// Whether this brand owns more than one usage pool (meter). Multi-pool
    /// brands render a brand header with nested sub-rows; single-pool brands
    /// render as one flat row.
    var isMultiPool: Bool { pools.count > 1 }

    /// Pools in display order — consumer/web surface first, CLI/secondary after.
    /// `pools` is an unordered Set, so multi-pool brands pin their order here.
    var orderedPools: [ProviderId] {
        switch self {
        case .openai: return [.chatgpt, .codex]
        case .google: return [.geminiConsumer, .gemini]
        default:      return ProviderId.allCases.filter { pools.contains($0) }
        }
    }

    /// The pool whose icon represents the brand in headers.
    var primaryPool: ProviderId { orderedPools.first ?? .claude }

    /// Display category for grouping on the Connections page. Multi-pool brands
    /// (OpenAI, Google) are platforms — the company is the platform, its web +
    /// CLI surfaces are sub-pools. Single-pool brands inherit their pool's category.
    var category: ProviderId.ProviderCategory {
        switch self {
        case .openai, .google: return .platforms
        default:               return primaryPool.category
        }
    }
}

extension ProviderId {
    /// The brand this ProviderId belongs to. Inverse of `BrandId.pools`.
    /// Deterministic — the brand → pools map is partitioned (no ProviderId
    /// appears in two brands), so this is well-defined.
    var brand: BrandId {
        switch self {
        case .claude:                        return .anthropic
        case .chatgpt, .codex:               return .openai
        case .gemini, .geminiConsumer:       return .google
        case .copilot:                       return .copilot
        case .cursor:                        return .cursor
        case .stableDiffusion:               return .stability
        case .midjourney:                    return .midjourney
        case .leonardo:                      return .leonardo
        case .runway:                        return .runway
        case .elevenlabs:                    return .elevenlabs
        case .suno:                          return .suno
        case .udio:                          return .udio
        case .grok:                          return .grok
        case .perplexity:                    return .perplexity
        }
    }
}

// MARK: - Connection State

/// Describes the current state of a provider's connection
enum ProviderConnectionState: Sendable, Equatable {
    case notInstalled
    case installedNoAuth
    case connected(plan: String)
    case authExpired
    case unavailable(reason: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .installedNoAuth: return "Not signed in"
        case .connected(let plan): return "\(plan) — Connected"
        case .authExpired: return "Auth expired"
        case .unavailable(let reason): return reason
        }
    }
}

// MARK: - Usage Snapshot

/// Provider-agnostic usage data that the UI renders
struct ProviderUsageSnapshot: Codable, Sendable {
    let shortWindow: WindowUsage
    /// Nil for providers that only expose a single usage metric (e.g. Copilot premium requests).
    let longWindow: WindowUsage?
    let planLabel: String
    let extraUsage: ExtraUsage?
    let creditsBalance: String?
}

/// A single usage window (e.g. 5-hour or 7-day)
struct WindowUsage: Codable, Sendable {
    let label: String
    let utilization: Double
    let resetsAt: Date
    let windowDuration: TimeInterval
    let sublabelOverride: String?

    init(label: String, utilization: Double, resetsAt: Date, windowDuration: TimeInterval, sublabelOverride: String? = nil) {
        self.label = label
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
        self.sublabelOverride = sublabelOverride
    }

    /// Pace: how far through the window we are (0–1).
    /// Returns 0 for non-time-based windows (e.g. context window) where pace is meaningless.
    var pace: Double {
        guard windowDuration > 0 else { return 0 }
        let remaining = max(resetsAt.timeIntervalSinceNow, 0)
        let elapsed = windowDuration - min(remaining, windowDuration)
        return min(max(elapsed / windowDuration, 0), 1)
    }

    /// Formatted time remaining until reset
    var timeUntilReset: String {
        if let override = sublabelOverride { return override }

        let interval = resetsAt.timeIntervalSinceNow
        guard interval > 0 else { return "Resetting now" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours >= 24 {
            let calendar = Calendar.current
            if calendar.isDateInToday(resetsAt) {
                return "Resets today"
            } else if calendar.isDateInTomorrow(resetsAt) {
                return "Resets tomorrow"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return "Resets \(formatter.string(from: resetsAt))"
            }
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
}

// MARK: - Per-Provider State (Published by ViewModel)

/// Everything the UI needs to render one provider's panel
struct ProviderState: Sendable {
    let connection: ProviderConnectionState
    let usage: ProviderUsageSnapshot?
    let error: AppError?
    let lastSynced: Date?
    let isLoading: Bool

    static let empty = ProviderState(
        connection: .notInstalled,
        usage: nil,
        error: nil,
        lastSynced: nil,
        isLoading: false
    )
}

// MARK: - Provider Protocol

/// Abstraction for any AI coding tool usage provider
protocol UsageProvider: Actor {
    var id: ProviderId { get }

    /// How often this provider should be polled (seconds).
    /// Local providers can use short intervals; remote APIs should use longer ones.
    var pollInterval: TimeInterval { get }

    /// Check whether the CLI is installed and authenticated
    func checkConnection() async -> ProviderConnectionState

    /// Fetch the latest usage data. Throws on failure.
    func fetchUsage() async throws -> ProviderUsageSnapshot
}
