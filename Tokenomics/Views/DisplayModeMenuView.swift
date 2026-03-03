import SwiftUI

/// Dropdown menu for choosing Smart vs Individual menu bar display mode
struct DisplayModeMenuView: View {
    @ObservedObject var viewModel: UsageViewModel

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
                .font(.caption2)

            ForEach(viewModel.connectedProviders) { provider in
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
                    .font(.caption)
                    .imageScale(.small)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
