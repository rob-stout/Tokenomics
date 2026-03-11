import SwiftUI

/// Footer showing last sync time, refresh button, display mode picker, and settings gear
struct SyncFooterView: View {
    let lastSynced: Date?
    let isLoading: Bool
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let showDisplayMode: Bool
    var updateAvailable: Bool = false
    var isStale: Bool = false
    @ObservedObject var viewModel: UsageViewModel

    private var syncText: String {
        guard let lastSynced else { return "Not yet synced" }
        let interval = Date.now.timeIntervalSince(lastSynced)

        if interval < 60 {
            return "Updated just now"
        } else {
            let minutes = Int(interval / 60)
            if minutes >= 60 {
                let hours = minutes / 60
                return "Updated \(hours)h ago"
            }
            return "Updated \(minutes)m ago"
        }
    }

    var body: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                if isStale {
                    Text(syncText)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Refreshes every 10 min. Showing most recent available data.")
                } else {
                    Text(syncText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Refresh button
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
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
                    .frame(height: 12)

                DisplayModeMenuView(viewModel: viewModel)
                    .frame(height: 16)
            }

            Divider()
                .frame(height: 12)

            // Settings gear
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if updateAvailable {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
