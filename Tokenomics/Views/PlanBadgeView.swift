import SwiftUI

/// Small rounded badge showing the user's plan type.
/// When `onTap` is provided, the badge becomes a tappable button.
struct PlanBadgeView: View {
    let label: String
    var onTap: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                badgeContent
                    .opacity(isHovering ? 0.7 : 1)
                    .onHover { hovering in isHovering = hovering }
            }
            .buttonStyle(.plain)
        } else {
            badgeContent
        }
    }

    private var badgeContent: some View {
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
        PlanBadgeView(label: "Free", onTap: {})
    }
}
