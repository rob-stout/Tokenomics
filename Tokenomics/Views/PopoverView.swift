import SwiftUI
import ServiceManagement

/// Main popover content shown when clicking the menu bar icon
struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel

    // View-local state: launch-at-login is a UI preference, not usage data,
    // so it lives here rather than in UsageViewModel.
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            if !viewModel.isAuthenticated {
                LoginView()
            } else if viewModel.isLoading && viewModel.usageData == nil {
                loadingView
            } else if let error = viewModel.error, viewModel.usageData == nil {
                errorView(error)
            } else if let data = viewModel.usageData {
                usageContent(data)
            }

            Divider()

            // Footer
            SyncFooterView(
                lastSynced: viewModel.lastSynced,
                isLoading: viewModel.isLoading,
                onRefresh: { viewModel.refresh() }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Launch at Login toggle
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                // Single-argument onChange keeps macOS 13 compatibility.
                // The two-argument (oldValue, newValue) form requires macOS 14+.
                .onChange(of: launchAtLogin) { newValue in
                    LaunchAtLoginService.setEnabled(newValue)
                    // Re-read the live status in case SMAppService rejected the change
                    // (e.g. user denied in System Settings → Privacy & Security).
                    launchAtLogin = LaunchAtLoginService.isEnabled
                }

            Divider()

            // Quit button
            Button("Quit Tokenomics") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
        }
        .onAppear {
            viewModel.startPolling()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Tokenomics")
                .font(.headline)
                .fontWeight(.medium)

            Spacer()

            PlanBadgeView(label: viewModel.planLabel)
        }
    }

    // MARK: - Usage Content

    @ViewBuilder
    private func usageContent(_ data: UsageData) -> some View {
        VStack(spacing: 12) {
            UsageBarView(
                label: "5-Hour Window",
                utilization: data.fiveHour.utilization,
                sublabel: data.fiveHour.timeUntilReset
            )

            Divider()

            UsageBarView(
                label: "7-Day Window",
                utilization: data.sevenDay.utilization,
                sublabel: data.sevenDay.timeUntilReset
            )

            // Extra usage section
            if let extra = data.extraUsage, extra.isEnabled {
                Divider()
                extraUsageSection(extra)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func extraUsageSection(_ extra: ExtraUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Extra Usage")
                    .font(.subheadline)
                Spacer()
                Text("\(extra.usedCreditsFormatted) / \(extra.monthlyLimitFormatted)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle((extra.utilization ?? 0) >= 100 ? .red : .secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 6)

                    Capsule()
                        .fill((extra.utilization ?? 0) >= 100 ? Color.red : Color.orange)
                        .frame(
                            width: geometry.size.width * min((extra.utilization ?? 0) / 100.0, 1),
                            height: 6
                        )
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Loading & Error States

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading usage data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Label mirrors the recovery instruction in the error message so
            // the user's eye lands on the exact action they need to take next.
            Button(error.isTokenExpired ? "Refresh" : "Try Again") {
                viewModel.refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(24)
    }
}
