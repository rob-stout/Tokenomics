import SwiftUI

/// Dropdown menu for choosing Smart vs Individual menu bar display mode
struct DisplayModeMenuView: View {
    @ObservedObject var viewModel: UsageViewModel

    @Environment(\.tokenomicsTextSize) private var textSize

    var body: some View {
        Menu {
            // Header
            Text("Menu Bar Display")

            // Smart mode
            Button(action: { viewModel.setSmartMode() }) {
                HStack {
                    if viewModel.isSmartMode {
                        Image(systemName: "checkmark")
                    }
                    Text("Smart (most urgent)")
                }
            }

            Divider()

            // Pin a specific provider
            Label("Pin Tracker:", systemImage: "pin")
                .scaledFont(.caption2)

            ForEach(viewModel.visibleProviders) { provider in
                Button(action: { viewModel.togglePin(for: provider) }) {
                    HStack {
                        if viewModel.isPinned(provider) {
                            Image(systemName: "pin.fill")
                        }
                        Text(provider.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: viewModel.isSmartMode ? "circle.circle" : "pin.fill")
                    .scaledFont(.caption)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6 * textSize.iconScale, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 28 * textSize.iconScale, height: 28 * textSize.iconScale)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
