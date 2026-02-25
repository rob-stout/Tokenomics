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

            Text("Sign in to Claude Code first, then relaunch Tokenomics.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Link("Open Claude Code Docs", destination: URL(string: "https://code.claude.com/docs/en/setup")!)
                .font(.caption)
        }
        .padding()
    }
}

#Preview {
    LoginView()
        .frame(width: 320)
}
