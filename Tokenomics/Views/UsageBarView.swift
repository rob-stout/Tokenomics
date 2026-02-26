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

    private static let barHeight: CGFloat = 6

    @State private var animatedValue: Double = 0

    private var clampedTarget: Double {
        min(max(utilization / 100.0, 0), 1)
    }

    private var clampedPace: Double {
        min(max(pace, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Int(utilization))%")
                    .font(.title2)
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
                        .animation(.easeOut(duration: 0.5), value: animatedValue)

                    // Pace marker — circle matching bar diameter
                    if clampedPace > 0.01 && clampedPace < 0.99 {
                        Circle()
                            .fill(Color.white)
                            .frame(width: Self.barHeight, height: Self.barHeight)
                            .offset(x: barWidth * clampedPace - Self.barHeight / 2)
                    }
                }
            }
            .frame(height: Self.barHeight)

            Text(sublabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int(utilization)) percent, \(sublabel)")
        .onAppear {
            animatedValue = 0
            DispatchQueue.main.async {
                animatedValue = clampedTarget
            }
        }
        .onDisappear {
            animatedValue = 0
        }
        .onChange(of: utilization) { _ in
            animatedValue = clampedTarget
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        UsageBarView(label: "5-Hour Window", utilization: 45, pace: 0.3, sublabel: "Resets in 2h 30m")
        UsageBarView(label: "5-Hour Window", utilization: 79, pace: 0.65, sublabel: "Resets in 1h 24m")
        UsageBarView(label: "5-Hour Window", utilization: 95, pace: 0.9, sublabel: "Resets in 15m")
    }
    .padding()
    .frame(width: 320)
}
