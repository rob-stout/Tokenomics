import SwiftUI
import ServiceManagement

/// Main popover content shown when clicking the menu bar icon
struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel

    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var settingsExpanded = false
    @State private var showAbout = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            if showAbout {
                // About replaces the main content inline
                AboutView(onDismiss: { showAbout = false })
            } else {
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

                // Footer with sync status, refresh, and settings gear
                SyncFooterView(
                    lastSynced: viewModel.lastSynced,
                    isLoading: viewModel.isLoading,
                    onRefresh: { viewModel.refresh() },
                    settingsExpanded: $settingsExpanded
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Collapsible settings section
                if settingsExpanded {
                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .font(.caption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            // Single-argument onChange for macOS 13 compatibility
                            .onChange(of: launchAtLogin) { newValue in
                                LaunchAtLoginService.setEnabled(newValue)
                                launchAtLogin = LaunchAtLoginService.isEnabled
                            }

                        Divider()

                        Button("About Tokenomics") { showAbout = true }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)

                        Divider()

                        HStack {
                            Button("Quit Tokenomics") {
                                NSApplication.shared.terminate(nil)
                            }
                            .buttonStyle(.plain)
                            .font(.caption)

                            Spacer()

                            Text("v\(appVersion)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settingsExpanded)
        .background {
            // Hidden buttons to register keyboard shortcuts within the popover
            VStack {
                Button("") { viewModel.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
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
                pace: viewModel.fiveHourPace,
                sublabel: data.fiveHour.timeUntilReset
            )

            Divider()

            UsageBarView(
                label: "7-Day Window",
                utilization: data.sevenDay.utilization,
                pace: viewModel.sevenDayPace,
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
