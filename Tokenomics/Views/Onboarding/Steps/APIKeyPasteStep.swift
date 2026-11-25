import SwiftUI

/// "Paste your API key" screen — Pattern E step 2.
///
/// Layout matches mockup section 11 (.secure-input lines ~820–858) with the
/// same chrome conventions used by every other onboarding step view:
///   - h2 title + lede left-aligned
///   - Wide secure input row (mono 13px) with inline `.tokenInField` Paste button
///   - "Lost your key? Generate a new one →" text-link, centered helper
///   - WindowFooter: ← Back ghost-sm | "Save & connect" primary
struct APIKeyPasteStep: View {
    /// The provider's display name — used in helper text.
    var providerName: String

    /// URL to the provider's API key generation page.
    var helpURL: URL?

    /// Latest rejected paste, if any. Shown inline; a new value also stops the spinner.
    var failure: APIKeySubmitFailure?

    /// Called when the user taps "Save & connect" with a non-empty key.
    var onSubmit: (String) -> Void

    /// Called when the user taps Back.
    var onBack: (() -> Void)?

    @State private var apiKey: String = ""
    @State private var isSubmitting: Bool = false
    @FocusState private var fieldFocused: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title — h2, left-aligned
            Text("Paste your API key")
                .font(Tokens.Typography.Onboarding.h2)
                .foregroundStyle(Tokens.Color.text(scheme))

            // Lede — left-aligned
            Text("Saved to macOS Keychain. Tokenomics reads it only when checking your usage — never sends it anywhere else.")
                .font(Tokens.Typography.Onboarding.lede)
                .foregroundStyle(Tokens.Color.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tokens.Spacing.s2)

            // Secure input row with inline Paste button
            secureInputRow
                .padding(.top, Tokens.Spacing.s5) // 24pt breathing room

            if let failure {
                Text(failure.message)
                    .font(Tokens.Typography.Onboarding.small)
                    .foregroundStyle(Tokens.Color.danger(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Tokens.Spacing.s2)
            }

            // Re-open the provider's API keys page. Works for either case —
            // user lost the page after copying their key, or never got one
            // yet and wants to go back to grab one.
            if let url = helpURL {
                Link(destination: url) {
                    (Text("Need your key? ")
                        .foregroundColor(Tokens.Color.textMuted(scheme))
                     + Text("Open \(providerName)'s API keys page →")
                        .foregroundColor(Tokens.Color.accent(scheme)))
                        .font(Tokens.Typography.Onboarding.small)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, Tokens.Spacing.s3)
            }

            Spacer(minLength: Tokens.Spacing.s5)

            WindowFooter {
                if let onBack {
                    BackLink(action: onBack)
                }
            } trailing: {
                Button {
                    submitIfValid()
                } label: {
                    if isSubmitting {
                        // Branded spinner, sized to fit the button's primary
                        // text height. Color matches the primary button's
                        // foreground (`accentInk` — light cream on dark
                        // button in light mode, cyan in dark mode) so it's
                        // legible against the dark fill.
                        CircularSpinner(size: 16, color: Tokens.Color.accentInk(scheme))
                    } else {
                        Text("Save & connect")
                    }
                }
                .buttonStyle(.tokenPrimary)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: failure) { _, _ in isSubmitting = false }
    }

    // MARK: - Secure input row

    /// Mockup .secure-input (lines 820–858): bg surface, border-strong, r-sm,
    /// mono 13px. Focus: border accent, shadow ring (0 0 0 4px accent@18%).
    /// Inline Paste button uses the .tokenInField style.
    private var secureInputRow: some View {
        HStack(spacing: Tokens.Spacing.s1 + 2) { // 6pt gap
            SecureField("sk-••••••••••••••••••••••••••••", text: $apiKey)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .frame(maxWidth: .infinity)
                .onSubmit { submitIfValid() }

            Button("Paste") {
                if let clip = NSPasteboard.general.string(forType: .string) {
                    apiKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .buttonStyle(.tokenInField)
        }
        .padding(.leading, Tokens.Spacing.s4 - 2) // 14pt
        .padding(.trailing, Tokens.Spacing.s2)     // 8pt
        .padding(.vertical, Tokens.Spacing.s2)     // 8pt
        .background(Tokens.Color.surface(scheme))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .strokeBorder(
                    fieldFocused ? Tokens.Color.accent(scheme) : Tokens.Color.borderStrong(scheme),
                    lineWidth: 1
                )
        )
        .shadow(
            color: fieldFocused ? Tokens.Color.accent(scheme).opacity(0.18) : .clear,
            radius: 4, x: 0, y: 0
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }

    // MARK: - Helpers

    private func submitIfValid() {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSubmitting = true
        onSubmit(apiKey)

        // Failsafe: if the connector's check doesn't transition us off this
        // step or report a failure within 5 seconds (polling died),
        // reset isSubmitting so the user can re-enter and retry instead of
        // sitting on a forever-spinning button. On success the parent
        // re-renders to the connected screen and this state is moot.
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run { isSubmitting = false }
        }
    }
}

// MARK: - Preview

private let pasteKeyStepperItems: [OnboardingStepperItem] = [
    OnboardingStepperItem(label: "Checking tools", state: .completed),
    OnboardingStepperItem(label: "Get API key", state: .completed),
    OnboardingStepperItem(label: "Paste key", state: .active),
    OnboardingStepperItem(label: "Connection check", state: .upcoming),
]

#Preview("Paste API key — empty — light") {
    WindowChromePreview(title: "Connect Stability AI", stepperItems: pasteKeyStepperItems) {
        APIKeyPasteStep(
            providerName: "Stability AI",
            helpURL: URL(string: "https://platform.stability.ai/account/keys"),
            onSubmit: { _ in },
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.light)
}

#Preview("Paste API key — empty — dark") {
    WindowChromePreview(title: "Connect Stability AI", stepperItems: pasteKeyStepperItems) {
        APIKeyPasteStep(
            providerName: "Stability AI",
            helpURL: URL(string: "https://platform.stability.ai/account/keys"),
            onSubmit: { _ in },
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.dark)
}

#Preview("Paste API key — ElevenLabs — light") {
    WindowChromePreview(title: "Connect ElevenLabs", stepperItems: pasteKeyStepperItems) {
        APIKeyPasteStep(
            providerName: "ElevenLabs",
            helpURL: URL(string: "https://elevenlabs.io/app/settings/api-keys"),
            onSubmit: { _ in },
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.light)
}

#Preview("Paste API key — ElevenLabs — dark") {
    WindowChromePreview(title: "Connect ElevenLabs", stepperItems: pasteKeyStepperItems) {
        APIKeyPasteStep(
            providerName: "ElevenLabs",
            helpURL: URL(string: "https://elevenlabs.io/app/settings/api-keys"),
            onSubmit: { _ in },
            onBack: {}
        )
    }
    .frame(width: 720, height: 560)
    .preferredColorScheme(.dark)
}
