import SwiftUI

/// Custom progress bar with semantic color based on utilization level
struct UsageBarView: View {
    let label: String
    let utilization: Double
    let sublabel: String

    private var usageState: UsageState {
        UsageState(utilization: utilization)
    }

    private var clampedValue: Double {
        min(max(utilization / 100.0, 0), 1)
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
                    .foregroundStyle(usageState.color)
            }

            // Custom capsule progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 6)

                    Capsule()
                        .fill(usageState.color)
                        .frame(width: geometry.size.width * clampedValue, height: 6)
                }
            }
            .frame(height: 6)

            Text(sublabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        UsageBarView(label: "5-Hour Window", utilization: 45, sublabel: "Resets in 2h 30m")
        UsageBarView(label: "5-Hour Window", utilization: 79, sublabel: "Resets in 1h 24m")
        UsageBarView(label: "5-Hour Window", utilization: 95, sublabel: "Resets in 15m")
    }
    .padding()
    .frame(width: 320)
}
