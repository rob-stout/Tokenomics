import SwiftUI

/// Footer showing last sync time, refresh button, and settings gear
struct SyncFooterView: View {
    let lastSynced: Date?
    let isLoading: Bool
    let onRefresh: () -> Void
    @Binding var settingsExpanded: Bool

    private var syncText: String {
        guard let lastSynced else { return "Not yet synced" }
        let interval = Date.now.timeIntervalSince(lastSynced)

        if interval < 60 {
            return "Just synced"
        } else {
            let minutes = Int(interval / 60)
            return "Synced \(minutes)m ago"
        }
    }

    var body: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(syncText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(
                        isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                        value: isLoading
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isLoading)

            Button(action: { settingsExpanded.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(settingsExpanded ? .primary : .secondary)
        }
    }
}
