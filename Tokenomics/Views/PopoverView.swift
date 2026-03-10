import SwiftUI
import ServiceManagement

/// Main popover content shown when clicking the menu bar icon
struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var updaterService: UpdaterService

    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var showingGeminiPlanSetup = false
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.showAbout {
                AboutView(onDismiss: { viewModel.showAbout = false })
            } else if viewModel.showHowItWorks {
                HowItWorksView(onDismiss: { viewModel.showHowItWorks = false })
            } else if viewModel.showAIConnections {
                AIConnectionsView(viewModel: viewModel)
            } else if viewModel.showNotifications {
                NotificationsView(viewModel: viewModel)
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
        .animation(.easeInOut(duration: 0.2), value: viewModel.showNotifications)
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
            ) { provider, toIndex in
                viewModel.moveProvider(provider, toIndex: toIndex)
            }

            Spacer().frame(height: 4)
        } else {
            Divider()
        }

        // Content for selected provider (keyed on tab to reset animation state)
        if let state = viewModel.currentProviderState {
            providerContent(state)
                .id(viewModel.selectedTab)
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
            updateAvailable: updaterService.updateAvailable,
            isStale: viewModel.isShowingStaleData,
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
                PlanBadgeView(
                    label: usage.planLabel,
                    onTap: viewModel.selectedTab == .gemini
                        ? { showingGeminiPlanSetup = true }
                        : nil
                )
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
        } else if currentTab == .gemini && (SettingsService.geminiPlan == nil || showingGeminiPlanSetup) {
            GeminiPlanSetupView(
                currentPlan: SettingsService.geminiPlan,
                onConfirm: { plan in
                    SettingsService.geminiPlan = plan
                    showingGeminiPlanSetup = false
                    viewModel.refresh()
                },
                onCancel: SettingsService.geminiPlan != nil
                    ? { showingGeminiPlanSetup = false }
                    : nil
            )
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

            if let longWindow = usage.longWindow {
                Divider()

                UsageBarView(
                    label: longWindow.label,
                    utilization: longWindow.utilization,
                    pace: longWindow.pace,
                    sublabel: longWindow.timeUntilReset
                )
            }

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

            if provider.usesPATAuth {
                Button("Reconnect") {
                    viewModel.showAIConnections = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Text("Update your token in AI Connections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if provider.hasAutoAuth {
                Button("Open \(provider.tabLabel)") {
                    provider.openLoginInTerminal()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Text("Sign in to \(provider.displayName),\nthen click Refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
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

            Button(error.isTokenExpired ? "Refresh" : "Check Now") {
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
                // ── Preferences ──
                sectionLabel("Preferences")

                settingsRow(icon: "checkmark.square", label: "Launch at Login") {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { newValue in
                            LaunchAtLoginService.setEnabled(newValue)
                            launchAtLogin = LaunchAtLoginService.isEnabled
                        }
                }

                Divider().padding(.horizontal, 16)

                settingsNavRow(
                    icon: "circle.grid.2x2",
                    label: "AI Connections",
                    detail: "\(viewModel.connectedProviders.count) connected"
                ) {
                    viewModel.showAIConnections = true
                }

                Divider().padding(.horizontal, 16)

                settingsNavRow(
                    icon: "bell",
                    label: "Notifications",
                    detail: viewModel.notificationsSubtitle
                ) {
                    viewModel.showNotifications = true
                }

                // ── Learn ──
                sectionLabel("Learn")

                settingsNavRow(icon: "info.circle", label: "How It Works") {
                    viewModel.showHowItWorks = true
                }

                Divider().padding(.horizontal, 16)

                settingsNavRow(icon: "star", label: "About Tokenomics") {
                    viewModel.showAbout = true
                }

                Divider().padding(.horizontal, 16)

                // Report Bugs — opens external link
                Button {
                    if let url = URL(string: "https://github.com/rob-stout/Tokenomics/issues") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "ladybug")
                            .font(.caption)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.secondary)
                        Text("Report Bugs / Feedback")
                            .font(.caption)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }

            // ── Footer ──
            Divider()

            HStack {
                // Check for Updates
                Button(action: { updaterService.checkForUpdates() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text(updaterService.updateAvailable ? "Update Available" : "Check for Updates")
                            .font(.caption2)
                        if updaterService.updateAvailable {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!updaterService.canCheckForUpdates)

                Spacer()

                // Quit
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Settings Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func settingsRow(icon: String, label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func settingsNavRow(icon: String, label: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}
