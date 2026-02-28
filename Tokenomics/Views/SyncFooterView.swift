import SwiftUI

/// Footer showing last sync time, refresh button, display mode picker, and settings gear
struct SyncFooterView: View {
    let lastSynced: Date?
    let isLoading: Bool
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let showDisplayMode: Bool
    @ObservedObject var viewModel: UsageViewModel

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

            // Refresh button
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

            // Display mode dropdown (only with multiple providers)
            if showDisplayMode {
                Divider()
                    .frame(height: 14)

                DisplayModeMenuView(viewModel: viewModel)
            }

            Divider()
                .frame(height: 14)

            // Settings gear
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
