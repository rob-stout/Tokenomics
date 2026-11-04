import SwiftUI

// Reusable motion for the popover and onboarding. Values live in
// Tokens.Motion (cited to the brand guidelines' motion table); every effect
// here is skipped when the user has Reduce Motion on.

extension View {
    /// One-shot "pop" for a success mark the moment it appears.
    func successPop() -> some View {
        modifier(SuccessPopModifier())
    }

    /// Draws the eye once when an alert symbol appears (if `isEnabled`).
    func attentionOnAppear(_ isEnabled: Bool = true) -> some View {
        modifier(AttentionOnAppearModifier(isEnabled: isEnabled))
    }

    /// Small bounce each time the pointer moves onto the view.
    func bounceOnHover() -> some View {
        modifier(BounceOnHoverModifier())
    }
}

private struct SuccessPopModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    // Start small, overshoot, settle — set instantly, then animate.
                    LinearKeyframe(Tokens.Motion.successPopStart, duration: 0)
                    for step in Tokens.Motion.successPopScales {
                        SpringKeyframe(step.scale, duration: step.duration)
                    }
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                trigger += 1
            }
    }
}

private struct AttentionOnAppearModifier: ViewModifier {
    let isEnabled: Bool
    @State private var trigger = 0

    func body(content: Content) -> some View {
        Group {
            // Symbol effects already honor Reduce Motion on their own.
            if #available(macOS 15.0, *) {
                content.symbolEffect(.wiggle, options: .nonRepeating, value: trigger)
            } else {
                content.symbolEffect(.bounce, options: .nonRepeating, value: trigger)
            }
        }
        .onAppear { if isEnabled { trigger += 1 } }
    }
}

private struct BounceOnHoverModifier: ViewModifier {
    @State private var trigger = 0

    func body(content: Content) -> some View {
        content
            .symbolEffect(.bounce, options: .nonRepeating, value: trigger)
            .onHover { isInside in if isInside { trigger += 1 } }
    }
}
