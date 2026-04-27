import SwiftUI

/// First-launch screen — replaces the old OnboardingView's full-list layout
/// with a single-CTA welcome. Hero ring + value prop + Get Started button.
///
/// Routes to ProviderChooserView when the user taps Get Started.
struct WelcomeView: View {
    var onGetStarted: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                WelcomeRingView()
                    .padding(.top, 24)

                VStack(spacing: 4) {
                    Text("Track your AI usage")
                        .scaledFont(.subheadline)
                        .fontWeight(.semibold)

                    Text("at a glance from the menu bar.")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Get Started", action: onGetStarted)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 8)

                footer
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    /// Two-paragraph footer — provider list + Settings hint. The blank line
    /// between the two paragraphs is meaningful; don't merge them.
    private var footer: some View {
        VStack(spacing: 10) {
            Text("Works with **Anthropic, OpenAI, Google AI, GitHub Copilot, Cursor, Stability AI, Runway, ElevenLabs, Midjourney, Suno & Udio**.")
                .scaledFont(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Text("Add or remove providers anytime in **Settings → Connections**.")
                .scaledFont(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
