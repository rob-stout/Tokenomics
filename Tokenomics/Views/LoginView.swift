import SwiftUI

/// Shown when no OAuth token is found in Keychain
struct LoginView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("See your Claude usage at a glance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Sign in to Claude Code first, then click Refresh.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let docsURL = URL(string: "https://code.claude.com/docs/en/setup") {
                Link("Open Claude Code Docs", destination: docsURL)
                    .font(.caption)
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sign in required. Sign in to Claude Code first, then click Refresh.")
    }
}

#Preview {
    LoginView()
        .frame(width: 320)
}
