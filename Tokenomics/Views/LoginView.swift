import SwiftUI

/// Shown when no provider is connected — walks the user to the Providers screen
/// where they can install a CLI, paste a token, or enter an API key.
struct LoginView: View {
    var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: MenuBarRingsRenderer.image(
                fiveHourFraction: 0,
                sevenDayFraction: 0,
                fiveHourPace: 0,
                sevenDayPace: 0
            ))
            .scaleEffect(2.0)
            .frame(width: 44, height: 44)

            Text("Track your AI coding usage.")
                .scaledFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Connect a provider to start tracking. Most providers support an API key or CLI sign-in.")
                .scaledFont(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Connect a Provider") {
                viewModel.showAIConnections = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button("Refresh") {
                viewModel.refresh()
            }
            .buttonStyle(.plain)
            .scaledFont(.caption)
            .foregroundStyle(.secondary)

            if let setupURL = URL(string: "https://trytokenomics.com/setup.html") {
                Link("View setup guide →", destination: setupURL)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Track your AI coding usage. Connect a provider to start tracking.")
    }
}
