import SwiftUI

extension UsageState {
    var color: Color {
        switch self {
        case .healthy: return .secondary
        case .caution: return .orange
        case .warning, .depleted: return .red
        case .error: return .red
        case .loading: return .secondary
        case .unauthenticated: return .secondary
        }
    }
}

/// Progress bar with pace indicator showing ideal even usage through the window.
struct UsageBarView: View {
    let label: String
    let utilization: Double
    let pace: Double
    let sublabel: String
    /// Changing this replays the build-in from zero (manual refresh).
    var replayTrigger: Int = 0

    private static let barHeight: CGFloat = 6

    @State private var animatedValue: Double = 0
    /// The number shown next to the label — counts up with the bar as it fills.
    @State private var displayedPercent: Double = 0
    /// The pace marker rides in from the left with the fill, so the eye
    /// follows it to its spot. It moves only when the pace itself does.
    @State private var animatedPace: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedTarget: Double {
        min(max(utilization / 100.0, 0), 1)
    }

    private var clampedPace: Double {
        min(max(pace, 0), 1)
    }

    private func fill() {
        withAnimation(reduceMotion ? nil : Tokens.Motion.barFill) {
            animatedValue = clampedTarget
            displayedPercent = utilization
        }
        withAnimation(reduceMotion ? nil : Tokens.Motion.paceSlide) {
            animatedPace = clampedPace
        }
    }

    private func reset() {
        animatedValue = 0
        displayedPercent = 0
        animatedPace = 0
    }

    private func replay() {
        reset()
        // Next runloop so the 0 state renders first and the fill animates.
        DispatchQueue.main.async { fill() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .scaledFont(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                CountUpPercent(value: displayedPercent)
                    .scaledFont(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Progress bar with pace indicator
            GeometryReader { geometry in
                let barWidth = geometry.size.width

                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: Self.barHeight)

                    // Fill
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: barWidth * animatedValue, height: Self.barHeight)

                    // Pace marker — runway indicator (time elapsed through the window)
                    if clampedPace > 0.01 && clampedPace < 0.99 {
                        Circle()
                            .fill(Color.white)
                            .frame(width: Self.barHeight, height: Self.barHeight)
                            .offset(x: barWidth * animatedPace - Self.barHeight / 2)
                    }
                }
            }
            .frame(height: Self.barHeight)

            Text(sublabel)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int(utilization)) percent, \(sublabel)")
        .onAppear { replay() }
        .onDisappear { reset() }
        .onChange(of: replayTrigger) { _, _ in
            guard !reduceMotion else { return }
            replay()
        }
        .onChange(of: utilization) { _, _ in
            fill()
        }
        .onChange(of: pace) { _, _ in
            fill()
        }
    }
}

/// Whole-number percent that counts through each value in place while
/// `value` animates. Animatable re-renders the text every frame with the
/// in-between value, so the digits tick rather than slide (`numericText`
/// rolls them vertically).
private struct CountUpPercent: View, Animatable {
    var value: Double

    // nonisolated: Animatable's requirement isn't main-actor bound, and this
    // only touches a plain stored Double.
    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value))%")
    }
}

#Preview {
    VStack(spacing: 20) {
        UsageBarView(label: "5-Hour Window", utilization: 45, pace: 0.3, sublabel: "Resets in 2h 30m")
        UsageBarView(label: "5-Hour Window", utilization: 79, pace: 0.65, sublabel: "Resets in 1h 24m")
        UsageBarView(label: "5-Hour Window", utilization: 95, pace: 0.9, sublabel: "Resets in 15m")
    }
    .padding()
    .frame(width: 360)
}
