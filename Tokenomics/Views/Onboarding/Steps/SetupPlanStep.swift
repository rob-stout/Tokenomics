import SwiftUI

/// Phase 3 onboarding review screen — "Your shortest path".
///
/// Shows the batched setup plan the router built from the user's MultiSelectStep
/// choices + detection results. Pure render layer: receives a `SetupPlan` and
/// displays it. Time math, ordering, and grouping happen upstream.
///
/// On Start → kick off batched execution.
/// On Back → return to MultiSelectStep with selections preserved.
///
/// Sized to fit the 720×560 onboarding window. Steps scroll if the plan grows
/// beyond what fits.
struct SetupPlanStep: View {
    let plan: SetupPlan

    /// Step numbers already completed — drives the checkboxes. Empty during the
    /// initial preview; fills in as the user returns from each connector.
    var completedSteps: Set<Int> = []
    /// True once "Start setup" has been tapped (execution underway). Switches the
    /// primary button from "Start setup" to "Continue" / "Show my usage".
    var hasStarted: Bool = false

    var onStart: () -> Void
    var onBack: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var allDone: Bool {
        !plan.steps.isEmpty && plan.steps.allSatisfy { completedSteps.contains($0.number) }
    }

    private var primaryTitle: String {
        if allDone { return "Show my usage" }
        return hasStarted ? "Continue" : "Start setup"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text("Your shortest path")
                    .font(Tokens.Typography.Onboarding.h2)
                    .foregroundStyle(Tokens.Color.text(scheme))

                Text(summaryLine)
                    .font(Tokens.Typography.Onboarding.lede)
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, Tokens.Spacing.s5)

            // Steps — scrolls if content overflows
            ScrollView {
                VStack(spacing: Tokens.Spacing.s4) {
                    ForEach(plan.steps) { step in
                        stepCard(step)
                    }
                }
                .padding(.bottom, Tokens.Spacing.s2)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: Tokens.Spacing.s3)

            // Footer — back + start
            WindowFooter {
                BackLink(action: onBack)
            } trailing: {
                Button(action: onStart) {
                    HStack(spacing: 4) {
                        Text(primaryTitle)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.tokenPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summaryLine: String {
        let providerWord = plan.providerCount == 1 ? "provider" : "providers"
        let stepWord = plan.stepCount == 1 ? "step" : "steps"
        return "Based on what you picked: \(plan.providerCount) \(providerWord) → \(plan.stepCount) \(stepWord), \(plan.estimatedDuration)."
    }

    // MARK: - Step card

    private func stepCard(_ step: SetupPlan.Step) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s4) {
            stepCheckbox(done: completedSteps.contains(step.number))

            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.title)
                        .font(Tokens.Typography.Onboarding.body.weight(.medium))
                        .foregroundStyle(Tokens.Color.text(scheme))
                    Spacer()
                    Text(step.timeEstimate)
                        .font(Tokens.Typography.Onboarding.small)
                        .foregroundStyle(Tokens.Color.textSubtle(scheme))
                }

                Text(step.description)
                    .font(.custom("DM Sans", size: 13))
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                if let covers = step.covers, !covers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(covers, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                    .font(.custom("DM Sans", size: 13))
                                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                                Text(item)
                                    .font(.custom("DM Sans", size: 13))
                                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(Tokens.Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Tokens.Color.surface(scheme))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .strokeBorder(Tokens.Color.border(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }

    /// Empty circle while pending; accent fill + checkmark once the step is done.
    /// (No "active" state — the live work happens on the connector screen; this
    /// screen is just the path tracker.)
    private func stepCheckbox(done: Bool) -> some View {
        ZStack {
            Circle()
                .fill(done ? Tokens.Color.accent(scheme) : Color.clear)
            Circle()
                .strokeBorder(
                    done ? Tokens.Color.accent(scheme) : Tokens.Color.borderStrong(scheme),
                    lineWidth: 1.5
                )
            if done {
                // On-accent foreground (ink900/white) — accentInk is the same cyan
                // as the fill in dark mode and would be invisible.
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Tokens.Color.ink900 : Color.white)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Preview

private struct SetupPlanPreviewWrapper: View {
    let plan: SetupPlan

    var body: some View {
        SetupPlanStep(plan: plan, onStart: {}, onBack: {})
            .padding(.top, Tokens.Spacing.s6)
            .padding(.horizontal, 40)
            .padding(.bottom, Tokens.Spacing.s5 + 4)
            .frame(width: 720, height: 560)
            .background(Tokens.DynamicColor.bg)
    }
}

private let typicalPlan = SetupPlan(
    providerCount: 4,
    stepCount: 3,
    estimatedDuration: "about a minute",
    steps: [
        .init(
            number: 1,
            title: "Install the Tokenomics browser extension",
            description: "Covers 2 of the tools you picked at once:",
            timeEstimate: "~1 min",
            covers: ["Claude (via claude.ai)", "ChatGPT (via chat.openai.com)"],
            launchTarget: .chatgpt
        ),
        .init(
            number: 2,
            title: "Confirm Claude Code is connected",
            description: "Already installed on your Mac — we just need to read your credentials.",
            timeEstimate: "~5 sec",
            covers: nil,
            launchTarget: .claude
        ),
        .init(
            number: 3,
            title: "Confirm Cursor is connected",
            description: "Already installed on your Mac — we just need to read your local data.",
            timeEstimate: "~5 sec",
            covers: nil,
            launchTarget: .cursor
        ),
    ]
)

private let singlePlan = SetupPlan(
    providerCount: 1,
    stepCount: 1,
    estimatedDuration: "about 30 seconds",
    steps: [
        .init(
            number: 1,
            title: "Paste your Stability AI API key",
            description: "We'll open stability.ai so you can grab a key, then come back to paste it here.",
            timeEstimate: "~30 sec",
            covers: nil,
            launchTarget: .stableDiffusion
        )
    ]
)

#Preview("Setup plan — typical — light") {
    SetupPlanPreviewWrapper(plan: typicalPlan)
        .preferredColorScheme(.light)
}

#Preview("Setup plan — typical — dark") {
    SetupPlanPreviewWrapper(plan: typicalPlan)
        .preferredColorScheme(.dark)
}

#Preview("Setup plan — single step — light") {
    SetupPlanPreviewWrapper(plan: singlePlan)
        .preferredColorScheme(.light)
}

#Preview("Setup plan — single step — dark") {
    SetupPlanPreviewWrapper(plan: singlePlan)
        .preferredColorScheme(.dark)
}
