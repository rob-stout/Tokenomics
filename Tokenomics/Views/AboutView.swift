import SwiftUI

/// About panel explaining the app and its UI elements.
/// Displayed inline within the popover, replacing the main content.
struct AboutView: View {
    let onDismiss: () -> Void

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

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

                Text("About")
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
                    Text("Tokenomics shows your AI coding tool usage at a glance from the menu bar. Supports Claude Code and Codex CLI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    sectionHeader("Menu Bar Icon")

                    legendRow(
                        icon: "circle.inset.filled",
                        title: "Outer Ring",
                        description: "Your 7-day rolling usage window. Fills as you use more of your weekly allowance."
                    )
                    legendRow(
                        icon: "circle.fill",
                        title: "Inner Ring",
                        description: "Your 5-hour rolling usage window. Fills as you use more of your short-term allowance."
                    )
                    legendRow(
                        icon: "smallcircle.filled.circle",
                        title: "Pace Dots",
                        description: "Show how far through each time window you are. If the dot is ahead of the fill, you're under pace. If behind, you're using faster than the window replenishes."
                    )
                    legendRow(
                        icon: "percent",
                        title: "Percentage",
                        description: "The 5-hour utilization as a number, shown next to the rings."
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
                        description: "When the usage window rolls over. The 5-hour window resets continuously; the 7-day window resets on a rolling basis."
                    )

                    Divider()

                    sectionHeader("Plan & Extras")

                    legendRow(
                        icon: "person.text.rectangle",
                        title: "Plan Badge",
                        description: "Shows your detected Claude plan: Free, Pro, or Max. Inferred from available API data."
                    )
                    legendRow(
                        icon: "dollarsign.circle",
                        title: "Extra Usage",
                        description: "Visible on Max plans with extra usage enabled. Shows how much of your monthly spending limit you've used."
                    )
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Text("Tokenomics v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
    AboutView(onDismiss: {})
        .frame(width: 320)
}
