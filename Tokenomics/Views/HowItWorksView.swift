import SwiftUI

/// Reference screen explaining how Tokenomics works and what UI elements mean.
/// Displayed inline within the popover, replacing the main content.
struct HowItWorksView: View {
    @Environment(\.tokenomicsTextSize) private var textSize

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .scaledFont(.caption)
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("How It Works")
                    .scaledFont(.headline)
                    .fontWeight(.medium)

                Spacer()

                // Invisible balance for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .scaledFont(.caption)
                .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Data fetching explanation
                    sectionHeader("How Tokenomics Fetches Data")

                    legendRow(
                        icon: "lock.shield",
                        title: "Local Only",
                        description: "Tokenomics reads credentials stored by each AI tool on your Mac, then calls their rate-limit APIs directly. No account is required in Tokenomics itself, and no data is sent to any server we operate. Your usage numbers never leave your machine."
                    )

                    Divider()

                    sectionHeader("Menu Bar Icon")

                    legendRow(
                        customIcon: "Outer Ring",
                        title: "Outer Ring",
                        description: "The broader picture \u{2014} a longer-horizon or secondary metric. For Claude it's the 7-day window; for Codex it's the model context window; for Gemini it's daily requests. Not all providers have two rings \u{2014} Copilot shows a single ring for AI credits."
                    )
                    legendRow(
                        customIcon: "Inner Ring",
                        title: "Inner Ring",
                        description: "Your most immediate constraint \u{2014} the limit you're closest to hitting. Fills clockwise as usage increases."
                    )
                    legendRow(
                        customIcon: "Pace Dots",
                        scale: 0.9,
                        title: "Pace Dots",
                        description: "Show where you'd be if usage were spread evenly across the period. Dot ahead of fill means you've got extra tokens to use. Dot in the fill means you'll run out of tokens before the period resets."
                    )
                    legendRow(
                        icon: "percent",
                        title: "Percentage",
                        description: "Your inner ring value as a number \u{2014} the limit you're closest to hitting."
                    )

                    Divider()

                    sectionHeader("Usage Panel")

                    legendRow(
                        customIcon: "Usage Bars",
                        title: "Usage Bars",
                        description: "Show how much of each rate limit window you've consumed. The bar fills from left to right as usage increases."
                    )
                    legendRow(
                        customIcon: "Pace Dots",
                        scale: 0.9,
                        title: "Pace Dots",
                        description: "Show where you'd be if usage were spread evenly across the period. Dot ahead of fill means you've got extra tokens to use. Dot in the fill means you'll run out of tokens before the period resets."
                    )
                    legendRow(
                        icon: "percent",
                        title: "Percentage",
                        description: "Your current utilization for each window, from 0% (fully available) to 100% (rate limited)."
                    )
                    legendRow(
                        icon: "clock.arrow.circlepath",
                        title: "Reset Time",
                        description: "When the current window resets. Time-based windows show a countdown; non-time-based windows (like context windows) show remaining capacity instead."
                    )

                    Divider()

                    sectionHeader("Plan & Extras")

                    legendRow(
                        customIcon: "Plan Badge",
                        title: "Plan Badge",
                        description: "Shows your plan tier for each provider. Claude, Codex, and Copilot plans are detected automatically. Gemini's plan is set by you and determines your daily rate limits."
                    )
                    legendRow(
                        icon: "dollarsign.circle",
                        title: "Extra Usage",
                        description: "Visible on Max plans with extra usage enabled. Shows how much of your monthly spending limit you've used."
                    )

                    Divider()

                    sectionHeader("Tips")

                    legendRow(
                        icon: "command",
                        title: "Reorder Tabs",
                        description: "Hold \u{2318} (Command) and drag a provider tab sideways to change its position in the popover. The new order saves automatically and also applies to your desktop widgets."
                    )

                    Divider()

                    sectionHeader("Desktop Widgets")

                    legendRow(
                        icon: "square.grid.2x2",
                        title: "Widget Extension",
                        description: "Tokenomics shares usage data with its own widget extension so you can add widgets to your desktop. macOS may ask to \"access data from other apps\" \u{2014} this is only your usage stats passing to the widget. No data leaves your Mac or is shared with any other app."
                    )

                    Divider()

                    sectionHeader("FAQ")

                    faqRow(
                        question: "Why don't I see a pace dot on some bars?",
                        answer: "Pace dots only appear on time-based windows. Things like Codex's context window don't reset on a schedule, so there's no pace to show. Runway, ElevenLabs, and Cursor also hide the dot when their API doesn't return a billing cycle date \u{2014} without that anchor, the math would be a guess."
                    )

                    faqRow(
                        question: "How does the menu bar decide which provider to show?",
                        answer: "By default, Smart mode shows whichever provider is closest to its limit \u{2014} so the most urgent thing is always visible. To always show one specific provider instead, click the display mode button in the popover footer and pick one under \u{201C}Pin Tracker.\u{201D}"
                    )
                }
                .padding(16)
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .scaledFont(.subheadline)
            .fontWeight(.semibold)
    }

    /// Q&A row — leading "Q"/"A" letters sit in the same column as the
    /// legend-row icons so the content column aligns across all sections.
    private func faqRow(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                faqLabel("Q")
                Text(question)
                    .scaledFont(.caption)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 10) {
                faqLabel("A")
                Text(answer)
                    .scaledFont(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func faqLabel(_ letter: String) -> some View {
        Text(letter)
            .scaledFont(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(width: 16 * textSize.iconScale, alignment: .center)
            .padding(.top, 1)
    }

    private func legendRow(
        icon: String,
        color: Color = .secondary,
        title: String,
        description: String
    ) -> some View {
        legendRow(
            iconView: Image(systemName: icon)
                .scaledFont(.caption)
                .foregroundStyle(color),
            title: title,
            description: description
        )
    }

    /// Custom-asset variant — pairs with the SVG imagesets in Assets.xcassets
    /// (template-rendered so they adopt the row's secondary color).
    /// `scale` lets individual icons nudge their visual weight without edits to the SVG.
    private func legendRow(
        customIcon: String,
        scale: CGFloat = 1.0,
        title: String,
        description: String
    ) -> some View {
        legendRow(
            iconView: Image(customIcon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 14 * textSize.iconScale * scale, height: 14 * textSize.iconScale * scale),
            title: title,
            description: description
        )
    }

    private func legendRow<Icon: View>(
        iconView: Icon,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            iconView
                .frame(width: 16 * textSize.iconScale, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(.caption)
                    .fontWeight(.medium)
                Text(description)
                    .scaledFont(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    HowItWorksView(onDismiss: {})
        .frame(width: 360)
}
