import SwiftUI

/// Numbered-checklist preview screen shown before handing off to an external
/// tool's wizard. Used for Windows 3 + 4 of the Anthropic / Claude Code flow.
///
/// Layout matches mockup section 12 Windows 3+4 (lines 2406–2532):
///   - h2 title + lede description, left-aligned, OUTSIDE the surface
///   - .surface card containing: uppercase group label ("IN CLAUDE CODE, YOU'LL:"),
///     the .wizard-list of numbered rows, and optional inline heads-up paragraph
///   - WindowFooter: ← Back ghost-sm | primary CTA
///
/// Item strings accept Markdown-formatted text (e.g. `**Pick login method** — ...`)
/// so the connector can bold individual phrases without splitting on punctuation.
struct PreviewExternalStepsView: View {
    /// Short headline.
    var headline: String

    /// One or two sentences setting context.
    var introText: String

    /// Uppercase header inside the surface card (e.g. "In Claude Code, you'll:").
    /// Nil hides the label.
    var groupLabel: String? = nil

    /// First wizard-row number. Window 3 starts at 1; Window 4 continues at 5.
    var startingNumber: Int = 1

    /// Ordered list of steps the user will take externally.
    /// Markdown-formatted: `**bold**` and `*italic*` render as expected.
    var items: [String]

    /// Label for the primary action button.
    var primaryLabel: String

    /// Optional advisory paragraph rendered INSIDE the surface card, below the list.
    var headsUp: String? = nil

    /// Called when the user taps the primary button.
    var onPrimary: () -> Void

    /// Called when the user taps Back.
    var onBack: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title — h2, left-aligned (mockup line 2435 `<h3 class="h-sans h2">`)
            Text(headline)
                .font(Tokens.Typography.Onboarding.h2)
                .foregroundStyle(Tokens.Color.text(scheme))

            // Lede description — mockup .lede margin-top 8px
            Text(introText)
                .font(Tokens.Typography.Onboarding.lede)
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tokens.Spacing.s2)

            // Surface card with group label + wizard list + optional heads-up
            // mockup .surface lines 374–379, per-frame margin-top: 18px
            surfaceCard
                .padding(.top, 18)

            Spacer(minLength: Tokens.Spacing.s5)

            WindowFooter {
                if let onBack {
                    BackLink(action: onBack)
                }
            } trailing: {
                Button(primaryLabel, action: onPrimary)
                    .buttonStyle(.tokenPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Surface card

    private var surfaceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Uppercase group label — mockup inline 11px textSubtle, weight 600,
            // tracking 0.08em, margin-bottom 10px (line 2443)
            if let label = groupLabel {
                Text(label)
                    .font(.custom("DM Sans", size: 11).weight(.semibold))
                    .tracking(0.88) // 0.08em ≈ 0.88pt at 11px
                    .textCase(.uppercase)
                    .foregroundStyle(Tokens.Color.textSubtle(scheme))
                    .padding(.bottom, Tokens.Spacing.s2 + 2) // 10pt
            }

            // Numbered wizard list — mockup .wizard-list: 10pt gap (line 866)
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2 + 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    wizardRow(number: startingNumber + index, text: item)
                }
            }

            // Inline heads-up paragraph — mockup line 2520: 12.5px textMuted,
            // margin-top 14px, line-height 1.5
            if let note = headsUp {
                Text(note)
                    .font(.custom("DM Sans", size: 12.5))
                    .foregroundStyle(Tokens.Color.textMuted(scheme))
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Tokens.Spacing.s4 - 2) // 14pt
            }
        }
        .padding(.horizontal, Tokens.Spacing.s4 + 2) // 18pt
        .padding(.vertical, Tokens.Spacing.s4)        // 16pt
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Color.surface(scheme))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Tokens.Color.border(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
    }

    // MARK: - Wizard row

    /// 22pt accent-tinted numbered circle + Markdown step text.
    /// mockup .w-num lines 874–885; .w-text 12.5px line 887.
    private func wizardRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s3) { // 12pt
            ZStack {
                Circle()
                    .fill(Tokens.Color.accent(scheme).opacity(0.14))
                    .frame(width: 22, height: 22)

                Text("\(number)")
                    .font(.custom("DM Sans", size: 11).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.Color.accent(scheme))
            }
            .padding(.top, 1) // optical alignment with first text line

            Text(parseMarkdown(text))
                .font(.custom("DM Sans", size: 12.5))
                .foregroundStyle(Tokens.Color.text(scheme))
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Parses inline Markdown (`**bold**`, `*italic*`) so connectors can specify
    /// emphasis per-phrase rather than splitting on punctuation.
    private func parseMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

// MARK: - Preview sample data
// Hoisted outside #Preview to avoid Swift type-checker timeout on large literals.

private let installStepperItems: [OnboardingStepperItem] = [
    OnboardingStepperItem(label: "Checking tools", state: .completed),
    OnboardingStepperItem(label: "Installing tools", state: .active),
    OnboardingStepperItem(label: "Signing in", state: .upcoming),
    OnboardingStepperItem(label: "Connection check", state: .upcoming),
]

private let window3Items: [String] = [
    "**Pick login method** — choose **Claude account with subscription** if you're on Pro / Max",
    "**Sign in via browser**, paste the email code Anthropic sends",
    "**Authorize** Claude Code to connect to your account",
    "**Accept** Anthropic's security notes",
]

private let window4Items: [String] = [
    "**Pick a folder** Claude can access — create a **Projects** folder in your *Home folder* if you don't have one",
    "**Grant macOS permissions** as Claude Code asks for them",
]

// MARK: - Preview

#Preview("Window 3 — Sign-in preview — light") {
    WindowChromePreview(title: "Connect Anthropic", stepperItems: installStepperItems) {
        PreviewExternalStepsView(
            headline: "Sign in to Claude Code",
            introText: "Next, sign in with your Anthropic account. Claude Code walks you through it in Terminal — here's what's going to happen:",
            groupLabel: "In Claude Code, you'll:",
            startingNumber: 1,
            items: window3Items,
            primaryLabel: "Continue",
            onPrimary: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.light)
}

#Preview("Window 3 — Sign-in preview — dark") {
    WindowChromePreview(title: "Connect Anthropic", stepperItems: installStepperItems) {
        PreviewExternalStepsView(
            headline: "Sign in to Claude Code",
            introText: "Next, sign in with your Anthropic account. Claude Code walks you through it in Terminal — here's what's going to happen:",
            groupLabel: "In Claude Code, you'll:",
            startingNumber: 1,
            items: window3Items,
            primaryLabel: "Continue",
            onPrimary: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.dark)
}

#Preview("Window 4 — Setup preview with headsUp — light") {
    WindowChromePreview(title: "Connect Anthropic", stepperItems: installStepperItems) {
        PreviewExternalStepsView(
            headline: "After you sign in",
            introText: "Claude Code asks for two more things — a folder and macOS permissions. Finish those and you're done.",
            groupLabel: "In Claude Code, you'll:",
            startingNumber: 5,
            items: window4Items,
            primaryLabel: "Open Terminal",
            headsUp: "Heads up: Claude Code asks macOS for access to a bunch of folders during setup — Music, Photos, Downloads, Documents. Safe to decline anything outside your Projects folder. Claude works fine without them.",
            onPrimary: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.light)
}

#Preview("Window 4 — Setup preview with headsUp — dark") {
    WindowChromePreview(title: "Connect Anthropic", stepperItems: installStepperItems) {
        PreviewExternalStepsView(
            headline: "After you sign in",
            introText: "Claude Code asks for two more things — a folder and macOS permissions. Finish those and you're done.",
            groupLabel: "In Claude Code, you'll:",
            startingNumber: 5,
            items: window4Items,
            primaryLabel: "Open Terminal",
            headsUp: "Heads up: Claude Code asks macOS for access to a bunch of folders during setup — Music, Photos, Downloads, Documents. Safe to decline anything outside your Projects folder. Claude works fine without them.",
            onPrimary: {},
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.dark)
}
