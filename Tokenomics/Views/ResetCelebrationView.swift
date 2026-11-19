import SwiftUI

/// Covers the popover when usage the user was waiting on resets, so the
/// confetti lands over a screen that says why. Same shape as onboarding's
/// connected screen (mark, headline, muted line, primary button), but in the
/// popover's own system text colors so it sits on the translucent material.
/// The popover hides its usage content underneath, keeping its size.
struct ResetCelebrationView: View {
    let celebration: ResetCelebration
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The pop on the 🎉 mark. `successPop()` (keyframes) left the mark blank
    /// in this overlay, so this is a plain spring from the same start scale.
    @State private var markScale = Tokens.Motion.successPopStart

    var body: some View {
        VStack(spacing: 0) {
            Text("🎉")
                .font(.system(size: 40))
                .scaleEffect(reduceMotion ? 1 : markScale)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { markScale = 1 }
                }
                .padding(.bottom, Tokens.Spacing.s4 + 2) // 18pt, as on the connected screen

            Text(celebration.title)
                .font(Tokens.Typography.Onboarding.h2)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(celebration.subtitle)
                .font(Tokens.Typography.Onboarding.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, Tokens.Spacing.s1)

            Button("Let's go", action: onDismiss)
                .buttonStyle(PopoverPillButtonStyle())
                .padding(.top, Tokens.Spacing.s5)
        }
        .padding(.horizontal, Tokens.Spacing.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Confetti falls behind the text and button. Skipped under Reduce Motion.
        // No fill of its own: the popover's material shows through, so the
        // screen reads as part of the popover rather than a jump to onboarding.
        .background {
            if !reduceMotion { ConfettiView() }
        }
        .contentShape(Rectangle())
    }
}

/// The primary button's pill shape and size in the popover's neutral, translucent
/// look (like the debug menu's buttons). The brand-blue fill read as out of place
/// on the popover material.
private struct PopoverPillButtonStyle: ButtonStyle {
    private let size = TokenButtonSize.regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .foregroundStyle(.primary)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.18 : 0.12)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: Tokens.Motion.fast), value: configuration.isPressed)
    }
}
