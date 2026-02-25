import SwiftUI

/// Small rounded badge showing the user's plan type
struct PlanBadgeView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tertiary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}

#Preview {
    HStack {
        PlanBadgeView(label: "Pro")
        PlanBadgeView(label: "Max")
        PlanBadgeView(label: "API")
    }
}
