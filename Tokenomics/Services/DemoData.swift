import Foundation

/// Static fixture data that populates every provider with realistic usage so the
/// full popover UI, menu-bar rings, and widgets can be reviewed without live API
/// credentials.
///
/// All utilization values are in the 0–100 range, matching `WindowUsage.utilization`.
/// Reset dates are set far enough in the future that the "resets in Xh Ym" sublabels
/// render plausibly without requiring a running clock.
enum DemoData {

    // MARK: - Snapshot Factory

    /// Returns a `ProviderUsageSnapshot` for every `ProviderId` that supports
    /// usage tracking. Providers with `supportsUsageTracking == false` are omitted.
    ///
    /// The spread is deliberate:
    /// - One near-limit (≥90%) to exercise warning color
    /// - One at exactly 100% to exercise the depleted/maxed state
    /// - Two remaining-only providers (zero utilization, sublabel override)
    /// - One `estimated: true` analogue via sublabelOverride
    static var allSnapshots: [ProviderId: ProviderUsageSnapshot] {
        [
            .claude: claudeSnapshot,
            .chatgpt: chatgptSnapshot,
            .codex: codexSnapshot,
            .gemini: geminiSnapshot,
            .geminiConsumer: geminiConsumerSnapshot,
            .copilot: copilotSnapshot,
            .cursor: cursorSnapshot,
            .elevenlabs: elevenLabsSnapshot,
            .midjourney: midjourneySnapshot,
            .grok: grokSnapshot,
            .perplexity: perplexitySnapshot,
            .leonardo: leonardoSnapshot,
            .runway: runwaySnapshot,
            .stableDiffusion: stableDiffusionSnapshot,
        ]
    }

    // MARK: - Scaled Snapshots

    /// Returns snapshots with all utilization values overridden to the given
    /// factor (0–100). Used by the debug menu "slam all to X%" control so Rob
    /// can eyeball color thresholds quickly.
    static func scaledSnapshots(utilization: Double) -> [ProviderId: ProviderUsageSnapshot] {
        let clamped = max(0, min(100, utilization))
        return allSnapshots.mapValues { snapshot in
            let short = overrideUtilization(snapshot.shortWindow, to: clamped)
            let long = snapshot.longWindow.map { overrideUtilization($0, to: clamped) }
            return ProviderUsageSnapshot(
                shortWindow: short,
                longWindow: long,
                planLabel: snapshot.planLabel,
                extraUsage: snapshot.extraUsage,
                creditsBalance: snapshot.creditsBalance
            )
        }
    }

    // MARK: - Individual Snapshots

    // Claude: 5-Hour 42%, 7-Day 18%
    private static var claudeSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "5-Hour Window",
                utilization: 42,
                resetsAt: futureDate(hours: 3.2),
                windowDuration: 5 * 3600
            ),
            longWindow: WindowUsage(
                label: "7-Day Window",
                utilization: 18,
                resetsAt: futureDate(days: 5),
                windowDuration: 7 * 24 * 3600
            ),
            planLabel: "Pro",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // ChatGPT: ~60%, estimated indicator (sublabelOverride signals the estimated state)
    private static var chatgptSnapshot: ProviderUsageSnapshot {
        // Mirrors the real extension reader's Plus shape: a 3-Hour GPT-5 message
        // window + a 7-day "Weekly Thinking" budget. Both are client-side
        // estimates (no public rate-limit API), hence the "estimated" sublabels.
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "3-Hour Window",
                utilization: 60,
                resetsAt: futureDate(hours: 2.5),
                windowDuration: 3 * 3600,
                sublabelOverride: "~60% estimated"
            ),
            longWindow: WindowUsage(
                label: "Weekly Thinking",
                utilization: 28,
                resetsAt: futureDate(hours: 24 * 4),
                windowDuration: 7 * 24 * 3600,
                sublabelOverride: "~28% estimated"
            ),
            planLabel: "Plus",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Codex: 5-Hour 30%
    private static var codexSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "5-Hour Window",
                utilization: 30,
                resetsAt: futureDate(hours: 4.1),
                windowDuration: 5 * 3600
            ),
            longWindow: WindowUsage(
                label: "Weekly",
                utilization: 12,
                resetsAt: futureDate(hours: 24 * 5 + 6),
                windowDuration: 7 * 24 * 3600
            ),
            planLabel: "Plus",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Gemini CLI: Tokens Today 55%, Requests Today 40%
    private static var geminiSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Tokens Today",
                utilization: 55,
                resetsAt: futureDate(hours: 8),
                windowDuration: 24 * 3600
            ),
            longWindow: WindowUsage(
                label: "Requests Today",
                utilization: 40,
                resetsAt: futureDate(hours: 8),
                windowDuration: 24 * 3600
            ),
            // Plan tier (Free/Standard/Enterprise), NOT a model name — mirrors the
            // real GeminiProvider, which uses the selected plan's displayLabel.
            planLabel: (SettingsService.geminiPlan ?? .free).displayLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Gemini consumer: 5-Hour 88%, Weekly 12%
    private static var geminiConsumerSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "5-Hour Window",
                utilization: 88,
                resetsAt: futureDate(hours: 0.8),
                windowDuration: 5 * 3600
            ),
            longWindow: WindowUsage(
                label: "Weekly",
                utilization: 12,
                resetsAt: futureDate(days: 6),
                windowDuration: 7 * 24 * 3600
            ),
            // Consumer (app) tier — label-only, set via the tappable plan badge.
            planLabel: (SettingsService.geminiConsumerPlan ?? .free).displayLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Copilot: 40% of monthly premium requests
    private static var copilotSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Premium Requests",
                utilization: 40,
                resetsAt: futureDate(days: 18),
                windowDuration: 30 * 24 * 3600
            ),
            longWindow: nil,
            planLabel: "Individual",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Cursor: 25%
    private static var cursorSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Monthly Requests",
                utilization: 25,
                resetsAt: futureDate(days: 22),
                windowDuration: 30 * 24 * 3600
            ),
            longWindow: nil,
            planLabel: "Pro",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // ElevenLabs: 95% — exercises warning color (near-limit)
    private static var elevenLabsSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Characters",
                utilization: 95,
                resetsAt: futureDate(days: 12),
                windowDuration: 31 * 24 * 3600,
                sublabelOverride: "95,000 / 100,000 used"
            ),
            longWindow: nil,
            planLabel: "Creator",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Midjourney: Fast Hours ~70%
    private static var midjourneySnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Fast Hours",
                utilization: 70,
                resetsAt: futureDate(days: 8),
                windowDuration: 30 * 24 * 3600,
                sublabelOverride: "4.2 / 6.0 hrs used"
            ),
            longWindow: nil,
            planLabel: "Standard",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Grok: 14 of 20 fast queries → 70%, shown as remaining
    private static var grokSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Fast Queries",
                utilization: 70,
                resetsAt: futureDate(hours: 36),
                windowDuration: 2 * 24 * 3600,
                sublabelOverride: "14 of 20 used"
            ),
            longWindow: nil,
            planLabel: "Premium",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Perplexity: remaining-only — 3 Pro searches left, utilization 0
    private static var perplexitySnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Pro Searches",
                utilization: 0,
                resetsAt: futureDate(hours: 18),
                windowDuration: 24 * 3600,
                sublabelOverride: "3 Pro left"
            ),
            longWindow: nil,
            planLabel: "Pro",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Leonardo: remaining-only — 150 tokens left, utilization 0
    private static var leonardoSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Tokens",
                utilization: 0,
                resetsAt: futureDate(days: 14),
                windowDuration: 30 * 24 * 3600,
                sublabelOverride: "150 tokens left"
            ),
            longWindow: nil,
            planLabel: "Artisan",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Runway: 100% — exercises the depleted/maxed visual state
    private static var runwaySnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Credits",
                utilization: 100,
                resetsAt: futureDate(days: 2),
                windowDuration: 30 * 24 * 3600,
                sublabelOverride: "500 / 500 used"
            ),
            longWindow: nil,
            planLabel: "Standard",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // Stable Diffusion: 55%
    private static var stableDiffusionSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Credits",
                utilization: 55,
                resetsAt: futureDate(days: 10),
                windowDuration: 30 * 24 * 3600
            ),
            longWindow: nil,
            planLabel: "Core",
            extraUsage: nil,
            creditsBalance: nil
        )
    }

    // MARK: - Helpers

    private static func futureDate(hours: Double = 0, days: Double = 0) -> Date {
        Date().addingTimeInterval(hours * 3600 + days * 24 * 3600)
    }

    private static func overrideUtilization(_ window: WindowUsage, to value: Double) -> WindowUsage {
        WindowUsage(
            label: window.label,
            utilization: value,
            resetsAt: window.resetsAt,
            windowDuration: window.windowDuration,
            sublabelOverride: window.sublabelOverride
        )
    }
}
