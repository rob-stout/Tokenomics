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
    // Coding Tools
    case copilot
    case cursor
    // Image Generation
    case stableDiffusion
    case midjourney
    // Video Generation
    case runway
    // Music / Audio / Voice
    case elevenlabs
    case suno
    case udio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Anthropic"
        case .chatgpt: return "ChatGPT"
        case .copilot: return "GitHub Copilot"
        case .cursor: return "Cursor"
        case .codex: return "OpenAI"
        case .gemini: return "Google AI"
        case .stableDiffusion: return "Stability AI"
        case .midjourney: return "Midjourney"
        case .runway: return "Runway"
        case .elevenlabs: return "ElevenLabs"
        case .suno: return "Suno"
        case .udio: return "Udio"
        }
    }

    /// Shorter name for tab bars where horizontal space is limited
    var tabLabel: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .copilot: return "Copilot"
        case .cursor: return "Cursor"
        case .codex: return "OpenAI"
        case .gemini: return "Google AI"
        case .stableDiffusion: return "Stability"
        case .midjourney: return "Midjourney"
        case .runway: return "Runway"
        case .elevenlabs: return "ElevenLabs"
        case .suno: return "Suno"
        case .udio: return "Udio"
        }
    }

    /// Short label for menu bar and tab icons.
    /// Most providers use a single letter; ChatGPT uses the full string because
    /// all single letters are already claimed by other providers.
    var shortLabel: String {
        switch self {
        case .claude: return "C"
        case .chatgpt: return "ChatGPT"
        case .copilot: return "P"
        case .cursor: return "U"
        case .codex: return "X"
        case .gemini: return "G"
        case .stableDiffusion: return "S"
        case .midjourney: return "M"
        case .runway: return "R"
        case .elevenlabs: return "E"
        case .suno: return "N"
        case .udio: return "D"
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
        case .chatgpt, .stableDiffusion, .midjourney, .runway, .elevenlabs, .suno, .udio: return ""
        }
    }

    /// Whether this provider exposes rate-limit / usage data
    var supportsUsageTracking: Bool {
        switch self {
        case .claude, .copilot, .cursor, .codex, .gemini: return true
        case .elevenlabs, .runway, .stableDiffusion: return true
        // chatgpt data arrives via the NMH bridge (browser-session), not a local API
        case .chatgpt: return true
        // When flipping any of these to `true`, update docs/PRIVACY.md —
        // the placeholder note currently tells users Tokenomics makes no
        // network calls or credential reads for these three.
        case .midjourney, .suno, .udio: return false
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
        case .chatgpt, .stableDiffusion, .midjourney, .runway, .elevenlabs, .suno, .udio: return ""
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
    }

    var category: ProviderCategory {
        switch self {
        case .claude, .chatgpt, .stableDiffusion: return .platforms
        case .copilot, .cursor, .codex, .gemini: return .codingTools
        case .midjourney: return .imageGeneration
        case .runway: return .videoGeneration
        case .elevenlabs, .suno, .udio: return .musicAudioVoice
        }
    }

    /// Whether this provider has a working data integration (false = "Coming Soon").
    /// chatgpt data arrives via the NMH bridge, not a direct API, so it counts as true.
    var hasAPI: Bool {
        switch self {
        case .midjourney, .suno, .udio: return false
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
        case .codex: return "Codex CLI"
        case .gemini: return "Gemini CLI"
        case .stableDiffusion: return "Stable Diffusion · Stable Image · Stable Video"
        default: return nil
        }
    }

    /// Anchor fragment that deep-links to the matching section of trytokenomics.com/setup.html
    var setupGuideAnchor: String {
        switch self {
        case .claude: return "#anthropic"
        case .chatgpt: return "#chatgpt"
        case .codex: return "#openai"
        case .gemini: return "#google"
        case .copilot: return "#copilot"
        case .cursor: return "#cursor"
        case .stableDiffusion, .runway, .elevenlabs: return "#api-key"
        case .midjourney, .suno, .udio: return ""
        }
    }

    /// Whether this provider authenticates via an API key stored in Keychain
    var usesAPIKeyAuth: Bool {
        switch self {
        case .elevenlabs, .runway, .stableDiffusion: return true
        default: return false
        }
    }

    /// Base name for icon assets (without the -white/-black/-d.blue suffix).
    /// Maps enum rawValues to actual file names in Provider Icons/.
    var iconBaseName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "chatgpt"
        case .codex: return "Codex"
        case .copilot: return "Copilot"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini"
        case .stableDiffusion: return "stability"
        case .midjourney: return "midjourney"
        case .runway: return "runway"
        case .elevenlabs: return "elevenlabs"
        case .suno: return "suno"
        case .udio: return "udio"
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
    case runway
    case elevenlabs
    case suno
    case udio

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
        case .runway:     return "Runway"
        case .elevenlabs: return "ElevenLabs"
        case .suno:       return "Suno"
        case .udio:       return "Udio"
        }
    }

    /// Corporate attribution shown as row sub-text. nil when the brand name
    /// already encodes the company (e.g. "Cursor", "Runway").
    var companyAttribution: String? {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai:    return "OpenAI"
        case .google:    return "Google"
        default:         return nil
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
        case .google:     return [.gemini]
        case .copilot:    return [.copilot]
        case .cursor:     return [.cursor]
        case .stability:  return [.stableDiffusion]
        case .midjourney: return [.midjourney]
        case .runway:     return [.runway]
        case .elevenlabs: return [.elevenlabs]
        case .suno:       return [.suno]
        case .udio:       return [.udio]
        }
    }
}

extension ProviderId {
    /// The brand this ProviderId belongs to. Inverse of `BrandId.pools`.
    /// Deterministic — the brand → pools map is partitioned (no ProviderId
    /// appears in two brands), so this is well-defined.
    var brand: BrandId {
        switch self {
        case .claude:           return .anthropic
        case .chatgpt, .codex:  return .openai
        case .gemini:           return .google
        case .copilot:          return .copilot
        case .cursor:           return .cursor
        case .stableDiffusion:  return .stability
        case .midjourney:       return .midjourney
        case .runway:           return .runway
        case .elevenlabs:       return .elevenlabs
        case .suno:             return .suno
        case .udio:             return .udio
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
