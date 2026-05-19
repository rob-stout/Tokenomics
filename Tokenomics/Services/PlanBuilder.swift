import Foundation

// MARK: - PlanBuilder

/// Generates a `SetupPlan` from the user's multi-select choices and detection results.
///
/// The plan groups selected brands into execution lanes to minimize friction:
///   - Extension batch: brands that can only be reached via the browser extension
///     (e.g. ChatGPT, Midjourney) — batched into one step regardless of count.
///   - CLI lane: brands with a local CLI tool (Claude Code, Codex, Gemini, Copilot,
///     Cursor) — one step per brand.
///   - API-key lane: brands authenticated via a pasted API key (Stability, Runway,
///     ElevenLabs) — one step per brand.
///
/// Step ordering: extension batch first, CLI steps next, API-key steps last.
/// This matches the user's expectation of "set up the shared thing first, then
/// the individual CLI tools, then the one-off keys."
struct PlanBuilder {

    // MARK: - Lane Classification

    /// Brands whose only connection path is the browser extension (no CLI, no API key).
    private static let extensionOnlyBrands: Set<BrandId> = [.openai, .midjourney]

    /// Brands connected via a local CLI tool or desktop app credentials.
    private static let cliBrands: Set<BrandId> = [.anthropic, .openai, .google, .copilot, .cursor]

    /// Brands connected via a pasted API key stored in Keychain.
    private static let apiKeyBrands: Set<BrandId> = [.stability, .runway, .elevenlabs]

    // MARK: - Build

    /// Produces a `SetupPlan` for the given selection and detection state.
    ///
    /// - Parameters:
    ///   - selection: The set of brands the user checked in MultiSelectStep.
    ///   - detection: Detection results from `DetectionService.detect()`. May be empty.
    /// - Returns: A `SetupPlan` with steps ordered for minimum user friction.
    static func build(
        selection: Set<BrandId>,
        detection: [BrandId: BrandDetection]
    ) -> SetupPlan {
        guard !selection.isEmpty else {
            return SetupPlan(
                providerCount: 0,
                stepCount: 0,
                estimatedDuration: "no setup needed",
                steps: []
            )
        }

        var steps: [SetupPlan.Step] = []
        var stepNumber = 1

        // --- Extension batch ---
        // Any selected brand that is extension-only AND has at least one provider
        // that is web-companion-delivered. OpenAI's pool includes both chatgpt
        // (extension-only) and codex (CLI) — for the extension step we only
        // advertise the web-companion pool members.
        let extensionBrands = selection.filter { brand in
            // A brand lands in the extension batch if any of its providers
            // is web-companion-only (not trackable without the extension).
            brand.pools.contains(where: isWebCompanionOnly)
        }
        if !extensionBrands.isEmpty {
            let coversList = extensionBrands.sorted(by: { $0.rawValue < $1.rawValue })
                .flatMap { brand in
                    brand.pools
                        .filter(isWebCompanionOnly)
                        .sorted(by: { $0.rawValue < $1.rawValue })
                        .map { coverLabelForWebProvider($0) }
                }
            let brandWord = coversList.count > 1 ? "\(coversList.count) of the tools you picked at once" : "one tool"
            steps.append(SetupPlan.Step(
                number: stepNumber,
                title: "Install the Tokenomics browser extension",
                description: "Covers \(brandWord):",
                timeEstimate: "~1 min",
                covers: coversList
            ))
            stepNumber += 1
        }

        // --- CLI steps (one per brand) ---
        // Brands that have CLI providers — includes OpenAI (codex CLI) even if
        // also in the extension batch, because codex is a separate pool that
        // needs its own credential setup.
        let cliSelection = selection
            .filter { cliBrands.contains($0) }
            .sorted(by: { $0.rawValue < $1.rawValue })

        for brand in cliSelection {
            let detected = detection[brand]?.isDetected == true
            let step = cliStep(brand: brand, detected: detected, number: stepNumber)
            steps.append(step)
            stepNumber += 1
        }

        // --- API-key steps (one per brand) ---
        let apiKeySelection = selection
            .filter { apiKeyBrands.contains($0) }
            .sorted(by: { $0.rawValue < $1.rawValue })

        for brand in apiKeySelection {
            let step = apiKeyStep(brand: brand, number: stepNumber)
            steps.append(step)
            stepNumber += 1
        }

        let providerCount = selection.reduce(0) { $0 + $1.pools.count }
        let duration = estimatedDuration(for: steps)

        return SetupPlan(
            providerCount: providerCount,
            stepCount: steps.count,
            estimatedDuration: duration,
            steps: steps
        )
    }

    // MARK: - Step Factories

    private static func cliStep(brand: BrandId, detected: Bool, number: Int) -> SetupPlan.Step {
        let title: String
        let description: String
        let timeEstimate: String

        if detected {
            switch brand {
            case .anthropic:
                title = "Confirm Claude Code is connected"
                description = "Already installed on your Mac — we just need to read your credentials."
                timeEstimate = "~5 sec"
            case .openai:
                title = "Confirm Codex CLI is connected"
                description = "Already installed on your Mac — we just need to read your credentials."
                timeEstimate = "~5 sec"
            case .google:
                title = "Confirm Gemini CLI is connected"
                description = "Already installed on your Mac — we just need to read your credentials."
                timeEstimate = "~5 sec"
            case .copilot:
                title = "Confirm GitHub Copilot is connected"
                description = "Already authenticated via gh CLI — we just need to read your token."
                timeEstimate = "~5 sec"
            case .cursor:
                title = "Confirm Cursor is connected"
                description = "Already installed on your Mac — we just need to read your local data."
                timeEstimate = "~5 sec"
            default:
                title = "Confirm \(brand.displayName) is connected"
                description = "Already installed on your Mac — we just need to read your credentials."
                timeEstimate = "~5 sec"
            }
        } else {
            switch brand {
            case .anthropic:
                title = "Set up Claude Code"
                description = "Install via npm and sign in."
                timeEstimate = "~2 min"
            case .openai:
                title = "Set up Codex CLI"
                description = "Install via npm and sign in."
                timeEstimate = "~2 min"
            case .google:
                title = "Set up Gemini CLI"
                description = "Install via npm and sign in."
                timeEstimate = "~2 min"
            case .copilot:
                title = "Set up GitHub Copilot"
                description = "Install the gh CLI via Homebrew and sign in."
                timeEstimate = "~2 min"
            case .cursor:
                title = "Set up Cursor"
                description = "Install Cursor via Homebrew and sign in."
                timeEstimate = "~2 min"
            default:
                title = "Set up \(brand.displayName)"
                description = "Install and sign in."
                timeEstimate = "~2 min"
            }
        }

        return SetupPlan.Step(
            number: number,
            title: title,
            description: description,
            timeEstimate: timeEstimate,
            covers: nil
        )
    }

    private static func apiKeyStep(brand: BrandId, number: Int) -> SetupPlan.Step {
        let siteName: String
        switch brand {
        case .stability:  siteName = "stability.ai"
        case .runway:     siteName = "runwayml.com"
        case .elevenlabs: siteName = "elevenlabs.io"
        default:          siteName = "\(brand.displayName.lowercased()).com"
        }

        return SetupPlan.Step(
            number: number,
            title: "Paste your \(brand.displayName) API key",
            description: "We'll open \(siteName) so you can grab a key, then come back to paste it here.",
            timeEstimate: "~30 sec",
            covers: nil
        )
    }

    // MARK: - Duration Estimation

    /// Produces a human-readable total duration string from the step estimates.
    ///
    /// Extension batch = 60s, CLI detected = 5s, CLI not detected = 120s,
    /// API key = 30s. The string is rounded and expressed naturally.
    private static func estimatedDuration(for steps: [SetupPlan.Step]) -> String {
        let totalSeconds = steps.reduce(0) { total, step in
            total + seconds(from: step.timeEstimate)
        }

        switch totalSeconds {
        case ..<30:
            return "under a minute"
        case 30..<90:
            return "about a minute"
        case 90..<150:
            return "~2 minutes"
        case 150..<210:
            return "~3 minutes"
        case 210..<270:
            return "~4 minutes"
        default:
            let minutes = (totalSeconds + 30) / 60  // round to nearest minute
            return "~\(minutes) minutes"
        }
    }

    /// Parses the numeric portion from a timeEstimate string like "~1 min", "~30 sec", "~5 sec".
    private static func seconds(from estimate: String) -> Int {
        let lowered = estimate.lowercased()
        // Strip leading tilde and extract the first integer token
        let digits = lowered.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
            .first ?? 0

        if lowered.contains("min") {
            return digits * 60
        } else {
            return digits
        }
    }

    // MARK: - Provider Classification Helpers

    /// True when a ProviderId is only accessible via the browser extension —
    /// it has no CLI tool and no local credentials path.
    private static func isWebCompanionOnly(_ provider: ProviderId) -> Bool {
        switch provider {
        case .chatgpt, .midjourney, .suno, .udio:
            return true
        default:
            return false
        }
    }

    /// Human-readable label for a web-companion-delivered provider used in the
    /// extension batch's "covers" list.
    private static func coverLabelForWebProvider(_ provider: ProviderId) -> String {
        switch provider {
        case .chatgpt:    return "ChatGPT (via chat.openai.com)"
        case .midjourney: return "Midjourney (via midjourney.com)"
        case .suno:       return "Suno (via suno.com)"
        case .udio:       return "Udio (via udio.com)"
        default:          return provider.displayName
        }
    }
}
