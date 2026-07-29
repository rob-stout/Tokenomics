import AppKit
import SwiftUI

// MARK: - ContentView

/// The companion's single window: enable-screen, live connection status, and
/// the "Get the full Mac app" funnel. Copy is verbatim from the approved
/// plan's copy appendix — voice is "calm, not clever," matching onboarding.
struct ContentView: View {
    @State private var status = SafariExtensionStatus()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                switch status.extensionState {
                case .enabled:
                    enabledContent
                case .disabled, .unknown:
                    disabledContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Spacing.s6)

            Divider()
                .overlay(Tokens.DynamicColor.border)

            funnelFooter
                .padding(Tokens.Spacing.s5)
        }
        .frame(width: 440)
        .background(Tokens.DynamicColor.bg)
        .onAppear { status.startObserving() }
        .onDisappear { status.stopObserving() }
    }

    // MARK: - Enable screen (not yet turned on in Safari)

    @ViewBuilder
    private var disabledContent: some View {
        Text("Turn on Tokenomics in Safari")
            .font(Tokens.Typography.Onboarding.h1)
            .foregroundStyle(Tokens.DynamicColor.text)

        Text("One switch and Tokenomics starts reading your web AI usage — ChatGPT, Gemini, Claude, and more — right in Safari.")
            .font(Tokens.Typography.Onboarding.lede)
            .foregroundStyle(Tokens.DynamicColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)

        Button("Open Safari Extensions…") {
            status.openSafariExtensionPreferences()
        }
        .buttonStyle(.tokenPrimaryLg)
        .padding(.top, Tokens.Spacing.s2)
    }

    // MARK: - Enabled state

    @ViewBuilder
    private var enabledContent: some View {
        Text("Tokenomics is on.")
            .font(Tokens.Typography.Onboarding.h1)
            .foregroundStyle(Tokens.DynamicColor.text)

        Text(freshnessText)
            .font(Tokens.Typography.Onboarding.body)
            .foregroundStyle(Tokens.DynamicColor.textMuted)
    }

    private var freshnessText: String {
        guard let lastHeartbeatAt = status.lastHeartbeatAt else {
            return "Waiting for your first visit to a supported site."
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: lastHeartbeatAt, relativeTo: Date())
        return "Last synced \(relative)."
    }

    // MARK: - Funnel footer (always shown)

    @ViewBuilder
    private var funnelFooter: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
            Text("Want menu-bar rings, desktop widgets, and your Claude Code, Codex, Copilot, and Cursor usage too?")
                .font(Tokens.Typography.Onboarding.small)
                .foregroundStyle(Tokens.DynamicColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button("Get the full Tokenomics app for Mac →") {
                openMacAppSite()
            }
            .buttonStyle(.tokenTextLink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openMacAppSite() {
        if let url = URL(string: "https://trytokenomics.com") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    ContentView()
}
