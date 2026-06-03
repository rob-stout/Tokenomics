import SwiftUI

/// Debug controls for beta and debug builds.
///
/// Entry point: a small "Debug" button in the popover footer, visible only when
/// `BuildInfo.showsDebugTools` is true. On stable release builds this entire file
/// still compiles but the entry point is hidden, so zero debug UI reaches users.
///
/// Controls:
/// - Demo mode on/off
/// - Brand aggregation flag on/off
/// - Reset onboarding
/// - Force refresh
/// - Slam all providers to a preset fill level (0 / 50 / 90 / 100%) to check
///   how the bars/rings render at each level (fill geometry + sublabel text;
///   bar color is fixed per window type, not utilization-based)
struct DebugMenuView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onDismiss: () -> Void

    @State private var brandAggFlag = FeatureFlags.brandAggregation

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 11))
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("Debug")
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                // Balance spacer (mirrors the Back button width)
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 11))
                .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: Demo Mode
                    sectionLabel("Demo Mode")

                    debugRow(icon: "theatermasks", label: "Demo mode") {
                        Toggle("", isOn: $viewModel.demoModeEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }

                    Text("Serves fixture data for all providers. Widgets + menu-bar rings also reflect demo data. OFF restores live polling.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    Divider().padding(.horizontal, 16)

                    // MARK: Slam Controls
                    sectionLabel("Slam All Providers")

                    HStack(spacing: 8) {
                        ForEach(DemoSlamPreset.allCases, id: \.self) { preset in
                            Button(preset.label) {
                                slam(to: preset.utilization)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Text("Overrides all demo provider bars to the selected utilization. Enables demo mode if not already on.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    Divider().padding(.horizontal, 16)

                    // MARK: Feature Flags
                    sectionLabel("Feature Flags")

                    debugRow(icon: "rectangle.3.group", label: "Brand aggregation") {
                        Toggle("", isOn: $brandAggFlag)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                            .onChange(of: brandAggFlag) {
                                FeatureFlags.brandAggregation = brandAggFlag
                            }
                    }

                    Divider().padding(.horizontal, 16)

                    // MARK: Actions
                    sectionLabel("Actions")

                    debugActionRow(icon: "arrow.counterclockwise", label: "Reset onboarding") {
                        SettingsService.hasCompletedOnboarding = false
                        // Reflect the change immediately in the VM without a full restart
                        viewModel.resetOnboardingForDebug()
                        onDismiss()
                    }

                    Divider().padding(.horizontal, 16)

                    debugActionRow(icon: "arrow.clockwise", label: "Force refresh now") {
                        viewModel.refresh()
                        onDismiss()
                    }
                }
            }
        }
        .onAppear {
            brandAggFlag = FeatureFlags.brandAggregation
        }
    }

    // MARK: - Slam

    private func slam(to utilization: Double) {
        // Activate demo mode first so applyDemoData calls are accepted
        if !viewModel.demoModeEnabled {
            viewModel.demoModeEnabled = true
        }
        // fireNotifications: true → run each provider through the threshold
        // evaluator so slamming to 90/100% actually triggers notifications.
        viewModel.applyDemoData(
            snapshots: DemoData.scaledSnapshots(utilization: utilization),
            fireNotifications: true
        )
        onDismiss()
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func debugRow(icon: String, label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 11))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func debugActionRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 11))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// MARK: - Slam Presets

private enum DemoSlamPreset: CaseIterable {
    case zero, half, high, maxed

    var label: String {
        switch self {
        case .zero:  return "0%"
        case .half:  return "50%"
        case .high:  return "90%"
        case .maxed: return "100%"
        }
    }

    var utilization: Double {
        switch self {
        case .zero:  return 0
        case .half:  return 50
        case .high:  return 90
        case .maxed: return 100
        }
    }
}
