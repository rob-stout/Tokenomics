import SwiftUI

/// Footer showing last sync time and refresh button
struct SyncFooterView: View {
    let lastSynced: Date?
    let isLoading: Bool
    let onRefresh: () -> Void

    private var syncText: String {
        guard let lastSynced else { return "Not yet synced" }
        let interval = Date.now.timeIntervalSince(lastSynced)

        if interval < 60 {
            return "Just synced"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "Synced \(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "Synced \(hours)h ago"
        }
    }

    var body: some View {
        HStack {
            Text(syncText)
                .font(.caption)
                .foregroundStyle(.tertiary)

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
        }
    }
}
