import SwiftUI

/// Provider-agnostic "connecting" screen for the browser-extension flow (stepper
/// step 3). Shown after the user taps Install while Tokenomics polls the bridge
/// for the extension's first heartbeat. Unlike `AwaitExternalAuthView` (which
/// draws a Claude-specific terminal illustration), this is generic — the
/// extension covers ChatGPT, Gemini, and more.
struct AwaitExtensionView: View {
    var headline: String
    var instructionText: String
    var onCheckNow: () -> Void
    var onBack: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .font(Tokens.Typography.Onboarding.h2)
                .foregroundStyle(Tokens.Color.text(scheme))

            Text(instructionText)
                .font(Tokens.Typography.Onboarding.lede)
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tokens.Spacing.s2)

            pollingPill
                .padding(.top, Tokens.Spacing.s5)

            Spacer(minLength: Tokens.Spacing.s5)

            WindowFooter {
                if let onBack {
                    BackLink(action: onBack)
                }
            } trailing: {
                Button("Check now", action: onCheckNow)
                    .buttonStyle(.tokenSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Dashed-border pill with a spinner — mirrors AwaitExternalAuthView's polling pill.
    private var pollingPill: some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.s2 + 2) { // 10pt
            CircularSpinner(size: 14, color: Tokens.Color.accent(scheme))

            Text("Watching for the extension to connect — this usually takes a few seconds.")
                .font(Tokens.Typography.Onboarding.small)
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Spacing.s4)       // 16pt
        .padding(.vertical, Tokens.Spacing.s4 - 2)     // 14pt
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Color.surface2(scheme))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .stroke(
                    Tokens.Color.borderStrong(scheme),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }
}

#Preview("Connecting — dark") {
    AwaitExtensionView(
        headline: "Connecting the extension",
        instructionText: "Once the extension is installed, it connects to Tokenomics automatically — usually within a few seconds.",
        onCheckNow: {},
        onBack: {}
    )
    .padding(.top, Tokens.Spacing.s6)
    .padding(.horizontal, 40)
    .padding(.bottom, Tokens.Spacing.s5 + 4)
    .frame(width: 720, height: 560)
    .background(Tokens.DynamicColor.bg)
    .preferredColorScheme(.dark)
}
