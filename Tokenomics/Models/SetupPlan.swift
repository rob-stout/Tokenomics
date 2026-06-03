import Foundation

/// Phase 3 onboarding plan — the batched setup path generated from the user's
/// multi-select choices and detection results. Built by the onboarding router
/// after `MultiSelectStep`, consumed by `SetupPlanStep` for the review screen.
///
/// One `Step` corresponds to one screen (or batched screen sequence) the user
/// will go through during execution. Steps are sequential and visible to the
/// user up-front, so the order should match the dispatch order.
struct SetupPlan {
    /// Total number of providers the plan covers — surfaced in the header
    /// line "X providers → N steps".
    let providerCount: Int

    /// Total number of execution steps — distinct from providerCount because
    /// one step (e.g. browser extension install) can cover multiple providers.
    let stepCount: Int

    /// Human-readable duration string ("about a minute", "~2 minutes", "~5 min").
    /// Pre-rendered by the planner so the view doesn't do time math.
    let estimatedDuration: String

    /// Ordered list of steps. Numbering starts at 1; the view trusts the order.
    let steps: [Step]

    struct Step: Identifiable {
        let number: Int
        let title: String
        let description: String
        /// Short estimate shown right-aligned next to the step title.
        let timeEstimate: String
        /// Optional bullet list shown below the description. Used for the
        /// extension-batch step to enumerate which providers it covers.
        let covers: [String]?
        /// The connector this step launches during hub-and-spoke execution.
        /// `.chatgpt` is the BrowserExtensionConnector's id (the extension batch);
        /// CLI/API-key steps carry their backing provider. Keeps the plan steps
        /// and execution targets aligned 1:1 — no separate ordered queue to drift.
        let launchTarget: ProviderId

        var id: Int { number }
    }
}
