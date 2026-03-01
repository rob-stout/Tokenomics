import SwiftUI

/// Shown when no OAuth token is found in Keychain
struct LoginView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Track your AI coding usage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Tokenomics reads your credentials automatically. Just sign in to at least one supported tool.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Connect") {
                viewModel.refresh()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            if let docsURL = URL(string: "https://code.claude.com/docs/en/setup") {
                Link("Setup Guide", destination: docsURL)
                    .font(.caption)
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Track your AI coding usage. Sign in to a supported tool, then tap Connect.")
    }
}
