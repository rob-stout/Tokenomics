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

            // Pin a specific provider (pool).
            //
            // Flag on: flat list of per-pool entries using pinTrackerLabel —
            //   e.g. "Anthropic / ChatGPT / Codex CLI / GitHub Copilot / Cursor / Gemini CLI"
            //   Pin storage stays at ProviderId granularity so old pins survive the upgrade.
            //
            // Flag off: per-ProviderId entries using displayName (today's behavior).
            Label("Pin Tracker:", systemImage: "pin")
                .scaledFont(.caption2)

            if FeatureFlags.brandAggregation {
                // Per-pool flat list — surfaces tool-specific names so users can pin
                // "Codex CLI" independently from "ChatGPT" within the same OpenAI brand.
                ForEach(viewModel.visibleProviders) { provider in
                    Button(action: { viewModel.togglePin(for: provider) }) {
                        HStack {
                            if viewModel.isPinned(provider) {
                                Image(systemName: "pin.fill")
                            }
                            Text(provider.pinTrackerLabel)
                        }
                    }
                }
            } else {
                // Today's per-ProviderId entries with displayName (e.g. "Anthropic",
                // "OpenAI", "Google AI"). Kept exactly as-is when the flag is off.
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
