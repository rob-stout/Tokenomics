import SwiftUI

/// Reference screen explaining how Tokenomics works and what UI elements mean.
/// Displayed inline within the popover, replacing the main content.
struct HowItWorksView: View {
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
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("How It Works")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                // Invisible balance for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.caption)
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
                        icon: "circle.inset.filled",
                        title: "Outer Ring",
                        description: "The broader picture \u{2014} a longer-horizon or secondary metric. For Claude it's the 7-day window; for Codex it's the model context window; for Gemini it's daily requests. Not all providers have two rings \u{2014} Copilot shows a single ring for premium requests."
                    )
                    legendRow(
                        icon: "circle.fill",
                        title: "Inner Ring",
                        description: "Your most immediate constraint \u{2014} the limit you're closest to hitting. Fills clockwise as usage increases."
                    )
                    legendRow(
                        icon: "smallcircle.filled.circle",
                        title: "Pace Dots",
                        description: "Show where you'd be if usage were spread evenly across the window. Dot ahead of fill means you're under pace. Dot behind fill means you're consuming faster than the window replenishes. Only shown on time-based windows."
                    )
                    legendRow(
                        icon: "percent",
                        title: "Percentage",
                        description: "Your inner ring value as a number \u{2014} the limit you're closest to hitting."
                    )

                    Divider()

                    sectionHeader("Usage Panel")

                    legendRow(
                        icon: "chart.bar.fill",
                        title: "Usage Bars",
                        description: "Show how much of each rate limit window you've consumed. The bar fills from left to right as usage increases."
                    )
                    legendRow(
                        icon: "circle.fill",
                        color: .white,
                        title: "Pace Indicator",
                        description: "The white dot on each bar marks where even usage would be at this point in the window. Helps you gauge whether to slow down or if you have room to work."
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
                        icon: "person.text.rectangle",
                        title: "Plan Badge",
                        description: "Shows your plan tier for each provider. Claude, Codex, and Copilot plans are detected automatically. Gemini's plan is set by you and determines your daily rate limits."
                    )
                    legendRow(
                        icon: "dollarsign.circle",
                        title: "Extra Usage",
                        description: "Visible on Max plans with extra usage enabled. Shows how much of your monthly spending limit you've used."
                    )

                    Divider()

                    sectionHeader("Desktop Widgets")

                    legendRow(
                        icon: "square.grid.2x2",
                        title: "Widget Extension",
                        description: "Tokenomics shares usage data with its own widget extension so you can add widgets to your desktop. macOS may ask to \"access data from other apps\" \u{2014} this is only your usage stats passing to the widget. No data leaves your Mac or is shared with any other app."
                    )
                }
                .padding(16)
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
    }

    private func legendRow(
        icon: String,
        color: Color = .secondary,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption2)
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
