import SwiftUI

/// Phase 3 onboarding screen — "What do you use AI for?"
///
/// Multi-select grouped by user activity (chat / code / image-video-audio).
/// Pre-checked rows reflect detection results from NSWorkspace bundle lookups
/// and local CLI presence checks. Detection annotations under each pre-checked
/// row tell the user *why* it was pre-checked, so they can override with context.
///
/// On Continue → `SetupPlanStep` (review screen).
/// On "Or set them up one at a time" → fall back to the existing chooser (Path A).
///
/// Sized to fit inside the 720×560 onboarding window. Categories scroll if
/// content exceeds the available height (rare with current provider set,
/// future-proof for more providers).
struct MultiSelectStep: View {
    /// User's current selection. Two-way binding so the parent owns state and
    /// the screen reflects external changes (e.g. pre-population from detection).
    @Binding var selected: Set<ProviderId>

    /// Per-provider detection annotation (e.g. ["claude": "signed in at claude.ai"]).
    /// Presence of a key signals "we detected this" — drives both pre-check and
    /// the sub-label. Empty dict = nothing detected; fresh-install experience.
    let detectionAnnotations: [ProviderId: String]

    var onContinue: () -> Void
    var onSetupOneAtATime: () -> Void
    var onBack: () -> Void

    @Environment(\.colorScheme) private var scheme

    private enum CategoryGroup {
        case multiPurpose
        case code
        case media

        var label: String {
            switch self {
            case .multiPurpose: return "AI you do multiple things with"
            case .code: return "AI you code with"
            case .media: return "AI for images, video, or audio"
            }
        }
    }

    private struct Row: Identifiable {
        let provider: ProviderId
        let label: String
        /// Persistent attribution shown as row sub-text (e.g. "Anthropic").
        /// When detection also yields an annotation, the two join on one line
        /// with " · ".
        let subLabel: String?
        var id: ProviderId { provider }
    }

    /// Provider → category map. Source of truth for which rows appear and where.
    ///
    /// Rows are **brand-level**, not pool-level. The "ChatGPT" row's primary
    /// `ProviderId` is `.chatgpt`, but the brand also covers Codex CLI usage
    /// (`.codex`); the planner/router resolves each brand to its full
    /// ProviderId set downstream. Popover tabs follow the same brand grouping
    /// and surface the pools as separate progress sections; widgets render
    /// per-pool because their layout is more constrained.
    ///
    /// Suno and Udio are omitted until they have working data paths — adding
    /// them here when their connectors land is the only change needed.
    private var groups: [(CategoryGroup, [Row])] {
        [
            (.multiPurpose, [
                Row(provider: .claude,  label: "Claude",  subLabel: "Anthropic"),
                Row(provider: .chatgpt, label: "ChatGPT", subLabel: "OpenAI"),
                Row(provider: .gemini,  label: "Gemini",  subLabel: "Google"),
            ]),
            (.code, [
                Row(provider: .copilot, label: "GitHub Copilot", subLabel: nil),
                Row(provider: .cursor,  label: "Cursor",         subLabel: nil),
            ]),
            (.media, [
                Row(provider: .stableDiffusion, label: "Stability AI", subLabel: nil),
                Row(provider: .midjourney,      label: "Midjourney",   subLabel: nil),
                Row(provider: .runway,          label: "Runway",       subLabel: nil),
                Row(provider: .elevenlabs,      label: "ElevenLabs",   subLabel: nil),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header block — title + lede
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text("What do you use AI for?")
                    .font(Tokens.Typography.Onboarding.h2)
                    .foregroundStyle(Tokens.Color.text(scheme))

                Text("We pre-checked anything we noticed on your Mac. Uncheck anything you don't use, or check what we missed.")
                    .font(Tokens.Typography.Onboarding.lede)
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, Tokens.Spacing.s5)

            // Categories — scrolls if content exceeds available height
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s5) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        categorySection(group.0, items: group.1)
                    }
                }
                .padding(.bottom, Tokens.Spacing.s2)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: Tokens.Spacing.s3)

            // Footer — back link + stacked primary CTA + secondary text link
            WindowFooter {
                BackLink(action: onBack)
            } trailing: {
                VStack(alignment: .trailing, spacing: Tokens.Spacing.s2) {
                    Button(action: onContinue) {
                        HStack(spacing: 4) {
                            Text("Show me my setup plan")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.tokenPrimary)
                    .disabled(selected.isEmpty)

                    Button("Or set them up one at a time", action: onSetupOneAtATime)
                        .buttonStyle(.tokenTextLink)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Category section

    private func categorySection(_ category: CategoryGroup, items: [Row]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
            Text(category.label)
                .font(Tokens.Typography.Onboarding.micro)
                .foregroundStyle(Tokens.Color.textSubtle(scheme))
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                    rowView(row)
                    if index < items.count - 1 {
                        Rectangle()
                            .fill(Tokens.Color.border(scheme))
                            .frame(height: 1)
                            .padding(.leading, Tokens.Spacing.s5 + 4)
                    }
                }
            }
            .background(Tokens.Color.surface(scheme))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                    .strokeBorder(Tokens.Color.border(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        }
    }

    // MARK: - Row

    private func rowView(_ row: Row) -> some View {
        let isSelected = selected.contains(row.provider)
        let subtext = composedSubtext(for: row)

        return Button {
            if isSelected {
                selected.remove(row.provider)
            } else {
                selected.insert(row.provider)
            }
        } label: {
            HStack(spacing: Tokens.Spacing.s3) {
                checkbox(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(Tokens.Typography.Onboarding.body)
                        .foregroundStyle(Tokens.Color.text(scheme))

                    if let subtext {
                        Text(subtext)
                            .font(.custom("DM Sans", size: 11))
                            .foregroundStyle(Tokens.Color.textSubtle(scheme))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, Tokens.Spacing.s3)
            .padding(.horizontal, Tokens.Spacing.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Joins persistent attribution (e.g. "Anthropic") and detection annotation
    /// (e.g. "signed in at claude.ai") into a single sub-text line. Either may
    /// be absent; both absent renders nothing.
    private func composedSubtext(for row: Row) -> String? {
        let annotation = detectionAnnotations[row.provider]
        switch (row.subLabel, annotation) {
        case let (.some(sub), .some(ann)): return "\(sub) · \(ann)"
        case let (.some(sub), .none):      return sub
        case let (.none, .some(ann)):      return ann
        case (.none, .none):               return nil
        }
    }

    private func checkbox(isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Tokens.Color.accent(scheme) : Color.clear)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelected ? Tokens.Color.accent(scheme) : Tokens.Color.borderStrong(scheme),
                    lineWidth: 1.5
                )
            if isSelected {
                // On-accent foreground must contrast the accent fill. accentInk
                // is the same cyan as the fill in dark mode (invisible), so mirror
                // the primary button's label color instead: ink900 / white.
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Tokens.Color.ink900 : Color.white)
            }
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - Preview

private struct MultiSelectPreviewWrapper: View {
    @State var selected: Set<ProviderId>
    let detectionAnnotations: [ProviderId: String]

    var body: some View {
        MultiSelectStep(
            selected: $selected,
            detectionAnnotations: detectionAnnotations,
            onContinue: {},
            onSetupOneAtATime: {},
            onBack: {}
        )
        .padding(.top, Tokens.Spacing.s6)
        .padding(.horizontal, 40)
        .padding(.bottom, Tokens.Spacing.s5 + 4)
        .frame(width: 720, height: 560)
        .background(Tokens.DynamicColor.bg)
    }
}

private let detectedSample: [ProviderId: String] = [
    .claude: "Claude Code CLI · signed in at claude.ai",
    .chatgpt: "ChatGPT.app installed",
    .cursor: "Cursor.app installed"
]

#Preview("Multi-select — detections — light") {
    MultiSelectPreviewWrapper(
        selected: [.claude, .chatgpt, .cursor],
        detectionAnnotations: detectedSample
    )
    .preferredColorScheme(.light)
}

#Preview("Multi-select — detections — dark") {
    MultiSelectPreviewWrapper(
        selected: [.claude, .chatgpt, .cursor],
        detectionAnnotations: detectedSample
    )
    .preferredColorScheme(.dark)
}

#Preview("Multi-select — nothing detected — light") {
    MultiSelectPreviewWrapper(
        selected: [],
        detectionAnnotations: [:]
    )
    .preferredColorScheme(.light)
}

#Preview("Multi-select — nothing detected — dark") {
    MultiSelectPreviewWrapper(
        selected: [],
        detectionAnnotations: [:]
    )
    .preferredColorScheme(.dark)
}
