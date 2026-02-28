import SwiftUI

/// Dropdown menu for choosing Smart vs Individual menu bar display mode
struct DisplayModeMenuView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        Menu {
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

            // Individual providers
            Text("Individual:")
                .font(.caption2)

            ForEach(viewModel.connectedProviders) { provider in
                Button(action: { viewModel.togglePin(for: provider) }) {
                    HStack {
                        if viewModel.isPinned(provider) {
                            Image(systemName: "checkmark")
                        }
                        Text(provider.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "circle.circle")
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
    }
}
