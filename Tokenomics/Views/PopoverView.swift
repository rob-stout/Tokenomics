import SwiftUI
import ServiceManagement

/// Main popover content shown when clicking the menu bar icon
struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var updaterService: UpdaterService

    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var showingGeminiPlanSetup = false
    /// Reveals the hidden "Beta features" section in Settings. Set to `true`
    /// only when the user holds Option while opening Settings (checked in
    /// `settingsView.onAppear`). Resets when Settings closes.
    @State private var betaFeaturesVisible = false
    /// Mirrors `FeatureFlags.brandAggregation` for binding to the toggle UI.
    /// Initialized from UserDefaults each time Settings appears so flips from
    /// the `defaults write` command path stay in sync.
    @State private var brandAggregationFlag = FeatureFlags.brandAggregation
    @AppStorage("textSize") private var textSizeRaw: String = TextSize.compact.rawValue
    private var textSize: TextSize { TextSize(rawValue: textSizeRaw) ?? .compact }

    @Environment(\.openWindow) private var openWindow

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
            } else if viewModel.showTextSize {
                TextSizeView(onDismiss: { viewModel.showTextSize = false })
            } else if viewModel.showSettings {
                settingsView
            } else if !viewModel.hasCompletedOnboarding {
                // First-launch users: show a lightweight card that opens the
                // real onboarding window. The window persists across app-switches
                // (unlike this popover, which dismisses on focus loss).
                onboardingLauncherCard
            } else {
                mainContent
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showSettings)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showAIConnections)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showNotifications)
        .environment(\.tokenomicsTextSize, textSize)
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
        // Re-detect providers and select contextual tab when popover opens
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            viewModel.redetectProviders()
            viewModel.selectContextualTab()
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

        // Content for selected provider (keyed on tab to reset animation state).
        // When nothing is connected, skip straight to LoginView — otherwise the
        // not-installed provider state falls through to an infinite spinner.
        if !viewModel.isAuthenticated {
            LoginView(viewModel: viewModel)
        } else if let state = viewModel.currentProviderState {
            providerContent(state)
                .id(viewModel.selectedTab)
        } else {
            LoginView(viewModel: viewModel)
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
                .scaledFont(.headline)
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
                item: URL(string: "https://robrstout.com/work/tokenomics/")!,
                message: Text("I'm tracking my AI coding tool usage with Tokenomics!")
            ) {
                Image(systemName: "square.and.arrow.up")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Provider Content

    @ViewBuilder
    private func providerContent(_ state: ProviderState) -> some View {
        let currentTab = viewModel.selectedTab ?? .claude
        if case .notInstalled = state.connection {
            notConnectedView(for: currentTab, connection: state.connection)
        } else if case .installedNoAuth = state.connection {
            notConnectedView(for: currentTab, connection: state.connection)
        } else if state.isLoading && state.usage == nil {
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
                        .scaledFont(.subheadline)
                    Spacer()
                    Text("$\(balance)")
                        .scaledFont(.subheadline)
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
                    .scaledFont(.subheadline)
                Spacer()
                Text("\(extra.usedCreditsFormatted) / \(extra.monthlyLimitFormatted)")
                    .scaledFont(.caption)
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
                .scaledFont(.title2)
                .foregroundStyle(.orange)

            Text("\(provider.displayName) authentication expired")
                .scaledFont(.caption)
                .fontWeight(.semibold)

            Button("Reconnect") {
                OnboardingTarget.shared.preselected = provider
                openWindow(id: "onboarding")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Text("Tap to walk through reconnecting.\nTokenomics will detect it automatically.")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    // MARK: - Not Connected

    /// Shown for a tab whose provider isn't installed or signed in. Surfaces
    /// the install/sign-in CTA instead of an infinite spinner.
    private func notConnectedView(for provider: ProviderId, connection: ProviderConnectionState) -> some View {
        let isInstalled: Bool
        if case .installedNoAuth = connection { isInstalled = true } else { isInstalled = false }

        return VStack(spacing: 8) {
            Image(systemName: "link.badge.plus")
                .scaledFont(.title2)
                .foregroundStyle(.secondary)

            Text(isInstalled
                 ? "\(provider.displayName) isn't signed in"
                 : "\(provider.displayName) isn't set up yet")
                .scaledFont(.caption)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(isInstalled
                 ? "Sign in so Tokenomics can read your usage."
                 : "Install the CLI or paste a token to start tracking usage.")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Set Up \(provider.tabLabel)") {
                OnboardingTarget.shared.preselected = provider
                openWindow(id: "onboarding")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if let setupURL = URL(string: "https://trytokenomics.com/setup.html\(provider.setupGuideAnchor)") {
                Link("View setup guide →", destination: setupURL)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    // MARK: - Coming Soon

    private func comingSoonView(for provider: ProviderId) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .scaledFont(.title2)
                .foregroundStyle(.secondary)

            Text("Usage tracking coming soon")
                .scaledFont(.caption)
                .fontWeight(.semibold)

            Text("\(provider.displayName) doesn't expose rate-limit data yet. We'll add support as soon as it's available.")
                .scaledFont(.caption)
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
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .scaledFont(.title2)
                .foregroundStyle(.orange)

            Text(error.localizedDescription)
                .scaledFont(.caption)
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
                    .scaledFont(.caption)
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("Settings")
                    .scaledFont(.headline)
                    .fontWeight(.medium)

                Spacer()

                // Invisible balance for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .scaledFont(.caption)
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
                    icon: "plus.circle",
                    label: "Setup providers\u{2026}"
                ) {
                    openWindow(id: "onboarding")
                }

                Divider().padding(.horizontal, 16)

                settingsNavRow(
                    icon: "bell",
                    label: "Notifications",
                    detail: viewModel.notificationsSubtitle
                ) {
                    viewModel.showNotifications = true
                }

                Divider().padding(.horizontal, 16)

                settingsNavRow(
                    icon: "textformat.size",
                    label: "Text Size",
                    detail: textSize.displayName
                ) {
                    viewModel.showTextSize = true
                }

                // ── Providers ──
                providerVisibilitySection

                // ── Learn ──
                sectionLabel("Learn")

                settingsNavRow(icon: "info.circle", label: "How It Works") {
                    viewModel.showHowItWorks = true
                }

                Divider().padding(.horizontal, 16)

                settingsNavRow(icon: "star", label: "About Tokenomics") {
                    viewModel.showAbout = true
                }

                sectionLabel("Extras")

                // Report Bugs — opens external link
                Button {
                    if let url = URL(string: "https://github.com/rob-stout/Tokenomics/issues") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "ladybug")
                            .scaledFont(.caption)
                            .frame(width: 16 * textSize.iconScale, height: 16 * textSize.iconScale)
                            .foregroundStyle(.secondary)
                        Text("Report Bugs / Feedback")
                            .scaledFont(.caption)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)

                Divider().padding(.horizontal, 16)

                Button(action: {
                    // Activate the app so Sparkle's update window appears above the popover
                    // without the popover dismissing and swallowing the interaction
                    NSApp.activate(ignoringOtherApps: true)
                    updaterService.checkForUpdates()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .scaledFont(.caption)
                            .frame(width: 16 * textSize.iconScale, height: 16 * textSize.iconScale)
                            .foregroundStyle(.secondary)
                        Text(updaterService.updateAvailable ? "Update Available" : "Check for Updates")
                            .scaledFont(.caption)
                        if updaterService.updateAvailable {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                        }
                        Spacer()
                        Text("v\(appVersion)")
                            .scaledFont(.caption)
                            .foregroundStyle(.quaternary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!updaterService.canCheckForUpdates)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)

                Divider().padding(.horizontal, 16)

                // ── Beta Features (hidden — hold Option while opening Settings) ──
                if betaFeaturesVisible {
                    betaFeaturesSection
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "power")
                            .scaledFont(.caption)
                            .frame(width: 16 * textSize.iconScale, height: 16 * textSize.iconScale)
                            .foregroundStyle(.secondary)
                        Text("Quit Tokenomics")
                            .scaledFont(.caption)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
        }
        .onAppear {
            // Reveal the Beta features section only if Option is held when
            // Settings opens. This is the documented "Option-click Settings"
            // entry point — once the section is visible, the toggle value
            // persists in UserDefaults regardless of whether the section is
            // shown on the next open.
            betaFeaturesVisible = NSEvent.modifierFlags.contains(.option)
            brandAggregationFlag = FeatureFlags.brandAggregation
        }
    }

    // MARK: - Beta Features Section

    /// Hidden section in Settings revealed by holding Option while opening
    /// the Settings panel. Houses runtime feature flags for in-flight UX
    /// changes that need an easy rollback while stabilizing. See
    /// `Services/FeatureFlags.swift`.
    @ViewBuilder
    private var betaFeaturesSection: some View {
        sectionLabel("Beta features")

        settingsRow(icon: "rectangle.3.group", label: "Brand aggregation") {
            Toggle("", isOn: $brandAggregationFlag)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .onChange(of: brandAggregationFlag) { newValue in
                    FeatureFlags.brandAggregation = newValue
                }
        }

        Text("Groups ChatGPT chat + Codex CLI (and Gemini chat + CLI) under one brand tab in the popover, with stacked progress sections inside. Affects medium / large widgets and the Pin Tracker dropdown too. Off = today's per-provider layout.")
            .scaledFont(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.bottom, 9)

        Divider().padding(.horizontal, 16)
    }

    // MARK: - Onboarding Launcher Card

    /// Shown in the popover before the user completes setup.
    /// Tapping the button opens the persistent onboarding window.
    ///
    /// The help banner style matches mockup .popover-help (lines 703–712):
    ///   bg accent@8%, 11×16 padding, 12.5px text-muted copy, accent link.
    private var onboardingLauncherCard: some View {
        let connected = viewModel.connectedProviders.count
        let total = viewModel.installedProviders.count + viewModel.connectedProviders.count
        let subtitle: String = connected == 0
            ? "Connect your AI coding tools to start tracking usage."
            : "\(connected) of \(max(connected, total)) providers connected."

        return VStack(spacing: 10) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 26))
                .foregroundStyle(Tokens.Color.brand600)
                .padding(.bottom, 2)

            Text("Set up your providers")
                .font(Tokens.Typography.App.sectionTitle)
                .foregroundStyle(Tokens.DynamicColor.text)

            Text(subtitle)
                .font(Tokens.Typography.App.caption)
                .foregroundStyle(Tokens.DynamicColor.textMuted)
                .multilineTextAlignment(.center)

            // Help banner inline — same accent@8% tint as popover-help
            HStack(spacing: 6) {
                Text("Need help connecting?")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.DynamicColor.textMuted)
                Spacer()
                Button("Open the guided setup →") {
                    openWindow(id: "onboarding")
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Tokens.Color.brand600)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Tokens.Color.brand600.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
            .padding(.top, 4)

            Button("Skip for now") {
                viewModel.completeOnboarding()
            }
            .buttonStyle(.plain)
            .font(Tokens.Typography.App.tiny)
            .foregroundStyle(Tokens.DynamicColor.textSubtle)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Provider Visibility Section

    /// Per-provider toggle rows shown under the "Providers" settings header.
    /// Toggling writes to SettingsService, which notifies MacSideStateExporter via
    /// NotificationCenter — callers here don't need to reach the exporter directly.
    @ViewBuilder
    private var providerVisibilitySection: some View {
        sectionLabel("Providers")

        ForEach(ProviderId.allCases) { providerId in
            providerVisibilityRow(for: providerId)
            if providerId != ProviderId.allCases.last {
                Divider().padding(.horizontal, 16)
            }
        }
    }

    private func providerVisibilityRow(for providerId: ProviderId) -> some View {
        let isEnabled = SettingsService.visibility(for: providerId)?.enabled ?? true
        return HStack(spacing: 8) {
            ProviderIcon(provider: providerId)
                .frame(width: 16 * textSize.iconScale, height: 16 * textSize.iconScale)

            VStack(alignment: .leading, spacing: 1) {
                Text(providerId.displayName)
                    .scaledFont(.caption)
                if !isEnabled {
                    Text("Hidden in menu bar and popup")
                        .scaledFont(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { SettingsService.visibility(for: providerId)?.enabled ?? true },
                set: { newValue in SettingsService.setVisibility(newValue, for: providerId) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
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
        let iconSide = 16 * textSize.iconScale
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .scaledFont(.caption)
                .frame(width: iconSide, height: iconSide)
                .foregroundStyle(.secondary)
            Text(label)
                .scaledFont(.caption)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func settingsNavRow(icon: String, label: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        let iconSide = 16 * textSize.iconScale
        return Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .scaledFont(.caption)
                    .frame(width: iconSide, height: iconSide)
                    .foregroundStyle(.secondary)
                Text(label)
                    .scaledFont(.caption)
                Spacer()
                if let detail {
                    Text(detail)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .scaledFont(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}
