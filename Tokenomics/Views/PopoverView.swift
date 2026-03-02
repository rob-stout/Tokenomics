import SwiftUI
import ServiceManagement

/// Main popover content shown when clicking the menu bar icon
struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var updaterService: UpdaterService

    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.showAbout {
                AboutView(onDismiss: { viewModel.showAbout = false })
            } else if viewModel.showAIConnections {
                AIConnectionsView(viewModel: viewModel)
            } else if viewModel.showSettings {
                settingsView
            } else if !viewModel.hasCompletedOnboarding {
                OnboardingView(viewModel: viewModel)
            } else {
                mainContent
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showSettings)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showAIConnections)
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
        // Re-detect providers when popover opens (user may have signed in externally)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            viewModel.redetectProviders()
        }
        // Reset to home view when popover closes
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            viewModel.resetNavigation()
        }
    }

    // MARK: - Main Content (Tabs + Usage)

    @ViewBuilder
    private var mainContent: some View {
        // Header
        header
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

        // Tabs (only if multiple providers)
        if viewModel.showTabs {
            ProviderTabView(
                providers: viewModel.visibleProviders,
                selection: $viewModel.selectedTab
            )

            Spacer().frame(height: 4)
        } else {
            Divider()
        }

        // Content for selected provider
        if let state = viewModel.currentProviderState {
            providerContent(state)
        } else if !viewModel.isAuthenticated {
            LoginView(viewModel: viewModel)
        } else {
            loadingView
        }

        Divider()

        // Footer
        SyncFooterView(
            lastSynced: viewModel.lastSynced,
            isLoading: viewModel.isLoading,
            onRefresh: { viewModel.refresh() },
            onSettings: { viewModel.showSettings = true },
            showDisplayMode: viewModel.installedProviders.count > 1,
            viewModel: viewModel
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Tokenomics")
                .font(.headline)
                .fontWeight(.medium)

            Spacer()

            if let state = viewModel.currentProviderState,
               let usage = state.usage {
                PlanBadgeView(label: usage.planLabel)
            }

            ShareLink(
                item: URL(string: "https://github.com/rob-stout/Tokenomics")!,
                message: Text("I'm tracking my AI coding tool usage with Tokenomics!")
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Provider Content

    @ViewBuilder
    private func providerContent(_ state: ProviderState) -> some View {
        let currentTab = viewModel.selectedTab ?? .claude
        if state.isLoading && state.usage == nil {
            loadingView
        } else if case .authExpired = state.connection {
            authExpiredView(for: currentTab)
        } else if !currentTab.supportsUsageTracking {
            comingSoonView(for: currentTab)
        } else if let error = state.error, state.usage == nil {
            errorView(error)
        } else if let usage = state.usage {
            usageContent(usage)
        } else {
            loadingView
        }
    }

    @ViewBuilder
    private func usageContent(_ usage: ProviderUsageSnapshot) -> some View {
        VStack(spacing: 12) {
            UsageBarView(
                label: usage.shortWindow.label,
                utilization: usage.shortWindow.utilization,
                pace: usage.shortWindow.pace,
                sublabel: usage.shortWindow.timeUntilReset
            )

            Divider()

            UsageBarView(
                label: usage.longWindow.label,
                utilization: usage.longWindow.utilization,
                pace: usage.longWindow.pace,
                sublabel: usage.longWindow.timeUntilReset
            )

            // Extra usage (Claude Max)
            if let extra = usage.extraUsage, extra.isEnabled {
                Divider()
                extraUsageSection(extra)
            }

            // Credits balance (Codex)
            if let balance = usage.creditsBalance {
                Divider()
                HStack {
                    Text("Credits Balance")
                        .font(.subheadline)
                    Spacer()
                    Text("$\(balance)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
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

    // MARK: - Auth Expired

    private func authExpiredView(for provider: ProviderId) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)

            Text("\(provider.displayName) authentication expired")
                .font(.caption)
                .fontWeight(.semibold)

            Button("Sign In") {
                provider.openLoginInTerminal()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Text("Opens Terminal to reconnect.\nTokenomics will detect it automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    // MARK: - Coming Soon

    private func comingSoonView(for provider: ProviderId) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Usage tracking coming soon")
                .font(.caption)
                .fontWeight(.semibold)

            Text("\(provider.displayName) doesn't expose rate-limit data yet. We'll add support as soon as it's available.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
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

            Button(error.isTokenExpired ? "Refresh" : "Try Again") {
                viewModel.refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(24)
    }

    // MARK: - Settings

    private var settingsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { viewModel.showSettings = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("Settings")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                // Invisible balance for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.caption)
                .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                // Launch at Login
                HStack {
                    Text("Launch at Login")
                        .font(.caption)
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { newValue in
                            LaunchAtLoginService.setEnabled(newValue)
                            launchAtLogin = LaunchAtLoginService.isEnabled
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                // AI Connections
                Button(action: { viewModel.showAIConnections = true }) {
                    HStack {
                        Text("AI Connections")
                            .font(.caption)
                        Spacer()
                        Text("\(viewModel.connectedProviders.count) connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                // Check for Updates
                Button("Check for Updates") { updaterService.checkForUpdates() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .disabled(!updaterService.canCheckForUpdates)

                Divider()

                // About
                Button("About Tokenomics") { viewModel.showAbout = true }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider()

                // Quit
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
                .padding(.vertical, 10)
            }
        }
    }
}
