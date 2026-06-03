import SwiftUI
import ServiceManagement

/// Main popover content shown when clicking the menu bar icon
struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var updaterService: UpdaterService

    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var showingGeminiPlanSetup = false
    /// Reveals the consumer Gemini (app) plan picker when its badge is tapped.
    @State private var showingGeminiConsumerPlanSetup = false
    /// Reveals the debug menu in beta/debug builds (gated on `BuildInfo.showsDebugTools`).
    @State private var showDebugMenu = false
    /// Presents the "Uninstall Tokenomics" confirmation alert.
    @State private var showingUninstallConfirm = false
    /// Reveals the hidden "Beta features" section in Settings. Set to `true`
    /// only when the user holds Option while opening Settings (checked in
    /// `settingsView.onAppear`). Resets when Settings closes.
    @State private var betaFeaturesVisible = false
    /// Mirrors `FeatureFlags.brandAggregation` for binding to the toggle UI.
    /// Initialized from UserDefaults each time Settings appears so flips from
    /// the `defaults write` command path stay in sync.
    @State private var brandAggregationFlag = FeatureFlags.brandAggregation
    /// Dismisses the "detected but not added" nudge banner for this popover
    /// session (resets when the popover closes via `resetNavigation`-adjacent
    /// state). Not persisted — a freshly detected tool should nudge again.
    @State private var dismissedDetectionNudge = false
    /// Selected brand when `FeatureFlags.brandAggregation` is on.
    /// Independent of `viewModel.selectedTab` (ProviderId) which drives the flag-off path.
    /// Initialized lazily to `enabledBrands.first` when the flag-on tab bar renders.
    @State private var selectedBrand: BrandId?
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
            } else if showDebugMenu && BuildInfo.showsDebugTools {
                DebugMenuView(viewModel: viewModel, onDismiss: { showDebugMenu = false })
            } else if viewModel.showSettings {
                settingsView
            } else if viewModel.connectedProviders.isEmpty && !viewModel.hasCompletedOnboarding {
                // True empty state only: nothing connected yet. Show a lightweight
                // card that opens the real onboarding window (it persists across
                // app-switches, unlike this popover). Once anything is connected we
                // fall through to mainContent — newly-detected-but-unadded tools are
                // surfaced there as a non-blocking banner instead of a takeover.
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
            // Sync selectedBrand when the flag is on: follow the worst-of-N or
            // pinned provider that selectContextualTab just chose.
            if FeatureFlags.brandAggregation {
                if let tab = viewModel.selectedTab {
                    selectedBrand = tab.brand
                } else {
                    selectedBrand = viewModel.enabledBrands.first
                }
            }
        }
        // Reset to home view when popover closes
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            viewModel.resetNavigation()
            showDebugMenu = false
            dismissedDetectionNudge = false
        }
    }

    // MARK: - Main Content (Tabs + Usage)

    /// True when there are tools detected on the machine the user hasn't added,
    /// at least one provider is already connected (so we're not in the takeover
    /// empty state), and the nudge hasn't been dismissed this session.
    private var showsDetectionNudge: Bool {
        UsageViewModel.showsDetectionNudge(
            dismissed: dismissedDetectionNudge,
            connectedCount: viewModel.connectedProviders.count,
            detectedCount: viewModel.detectedNotConnected.count
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        if showsDetectionNudge {
            detectionNudgeBanner
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }

        // Header
        header
            .padding(.horizontal, 16)
            .padding(.top, showsDetectionNudge ? 8 : 12)
            .padding(.bottom, 8)

        if FeatureFlags.brandAggregation {
            brandMainContent
        } else {
            legacyMainContent
        }

        Divider()

        // Footer (shared by both paths)
        SyncFooterView(
            lastSynced: viewModel.lastSynced,
            isLoading: viewModel.isLoading,
            onRefresh: { viewModel.refresh() },
            onSettings: { viewModel.showSettings = true },
            showDisplayMode: viewModel.installedProviders.count > 1,
            updateAvailable: updaterService.updateAvailable,
            isStale: viewModel.isShowingStaleData,
            viewModel: viewModel,
            onDebug: BuildInfo.showsDebugTools ? { showDebugMenu = true } : nil
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Brand-aware tab bar + body (flag on)

    /// Brand-aggregated tab bar + body. Shown when `FeatureFlags.brandAggregation` is on.
    /// Each tab represents one brand; the body stacks a usage section per pool beneath it.
    /// Tab height adapts naturally: single-pool brands render one block, multi-pool brands
    /// render N blocks separated by dividers.
    @ViewBuilder
    private var brandMainContent: some View {
        let brands = viewModel.enabledBrands

        // Brand tab bar (only when more than one brand is visible)
        if brands.count > 1 {
            BrandTabView(
                brands: brands,
                selection: $selectedBrand,
                onMove: { brand, toIndex in
                    viewModel.moveBrand(brand, toIndex: toIndex)
                }
            )
            Spacer().frame(height: 4)
        } else {
            Divider()
        }

        // Body: stack one usage section per pool for the selected brand.
        if !viewModel.isAuthenticated {
            LoginView(viewModel: viewModel)
        } else {
            let activeBrand = selectedBrand ?? brands.first
            if let brand = activeBrand {
                brandBody(for: brand)
                    // Key on the brand so SwiftUI resets animation state on tab switch
                    .id(brand)
                    .onAppear {
                        // Seed selectedBrand on first render if not yet set
                        if selectedBrand == nil {
                            selectedBrand = brand
                        }
                    }
            } else {
                LoginView(viewModel: viewModel)
            }
        }
    }

    /// Stacked pool sections for the given brand.
    /// Single-pool brands render exactly as the legacy path. Multi-pool brands
    /// show each pool's section separated by a hairline divider + pool label.
    @ViewBuilder
    private func brandBody(for brand: BrandId) -> some View {
        let pairs = viewModel.poolPairs(for: brand)

        if pairs.isEmpty {
            LoginView(viewModel: viewModel)
        } else if pairs.count == 1, let (providerId, state) = pairs.first {
            // Single-pool brand: identical rendering to the legacy per-provider path
            providerContent(state, providerId: providerId)
        } else {
            // Multi-pool brand: stack pool sections, separated by dividers with labels
            VStack(spacing: 0) {
                ForEach(Array(pairs.enumerated()), id: \.element.0) { index, pair in
                    let (providerId, state) = pair

                    // Pool header label + inline plan pill (tappable for Gemini pools)
                    poolSectionHeader(for: providerId, planLabel: planBadgeLabel(for: providerId, usage: state.usage))

                    providerContent(state, providerId: providerId)

                    if index < pairs.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    /// Slim label row identifying a pool within a multi-pool brand tab.
    /// Uses the pool's `tabLabel` which carries the tool-specific name
    /// (e.g. "ChatGPT", "OpenAI" for codex).
    private func poolSectionHeader(for providerId: ProviderId, planLabel: String?) -> some View {
        HStack {
            Text(providerId.poolLabel)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            Spacer()
            if let planLabel {
                PlanBadgeView(label: planLabel, onTap: planTapHandler(for: providerId))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: - Legacy per-provider tab bar + body (flag off)

    /// Original per-provider tab bar and body. Kept exactly as-is when the flag is off —
    /// this is the rollback path.
    @ViewBuilder
    private var legacyMainContent: some View {
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
            providerContent(state, providerId: viewModel.selectedTab ?? .claude)
                .id(viewModel.selectedTab)
        } else {
            LoginView(viewModel: viewModel)
        }
    }

    // MARK: - Header

    /// Usage snapshot for the active view, used by the plan badge.
    /// Brand mode: uses the first pool of the selected brand.
    /// Legacy mode: uses the currently selected provider tab.
    /// Plan badge for the popover header. In brand mode it appears ONLY for
    /// single-(visible-)pool brands; multi-pool brands show a pill per pool
    /// inline in each section header instead. `tapProvider` is the pool whose
    /// plan picker the badge opens (nil = non-tappable).
    private var activePlanLabel: (label: String, tapProvider: ProviderId?)? {
        if FeatureFlags.brandAggregation {
            let brand = selectedBrand ?? viewModel.enabledBrands.first
            guard let brand else { return nil }
            let pairs = viewModel.poolPairs(for: brand)
            // Multi-pool: pills live inline in the per-pool section headers.
            if pairs.count > 1 { return nil }
            guard let (providerId, state) = pairs.first, let usage = state.usage else { return nil }
            return (usage.planLabel, providerId)
        } else {
            guard let state = viewModel.currentProviderState, let usage = state.usage else { return nil }
            return (usage.planLabel, viewModel.selectedTab)
        }
    }

    /// The plan label to show on a pool's badge. For the consumer Gemini (app)
    /// pool the tier isn't readable from the web session (the extension sends a
    /// placeholder), so we use the user-chosen `geminiConsumerPlan` instead of the
    /// snapshot's label — making the picker authoritative in both live and demo.
    private func planBadgeLabel(for providerId: ProviderId, usage: ProviderUsageSnapshot?) -> String? {
        if providerId == .geminiConsumer {
            return (SettingsService.geminiConsumerPlan ?? .free).displayLabel
        }
        return usage?.planLabel
    }

    /// Returns the tap action that opens a pool's plan picker, or nil if the pool
    /// has no user-editable plan. Shared by the header badge and the inline
    /// per-pool section-header badges.
    private func planTapHandler(for providerId: ProviderId?) -> (() -> Void)? {
        switch providerId {
        case .gemini:         return { showingGeminiPlanSetup = true }
        case .geminiConsumer: return { showingGeminiConsumerPlanSetup = true }
        default:              return nil
        }
    }

    private var header: some View {
        HStack {
            Text("Tokenomics")
                .scaledFont(.headline)
                .fontWeight(.medium)

            Spacer()

            if let plan = activePlanLabel {
                PlanBadgeView(label: plan.label, onTap: planTapHandler(for: plan.tapProvider))
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

    /// Renders the content block for a single provider pool.
    /// `providerId` is passed explicitly so this can be called from both the legacy
    /// path (using `viewModel.selectedTab`) and the brand path (iterating pool pairs).
    @ViewBuilder
    private func providerContent(_ state: ProviderState, providerId: ProviderId) -> some View {
        if case .notInstalled = state.connection {
            notConnectedView(for: providerId, connection: state.connection)
        } else if case .installedNoAuth = state.connection {
            notConnectedView(for: providerId, connection: state.connection)
        } else if state.isLoading && state.usage == nil {
            loadingView
        } else if case .authExpired = state.connection {
            authExpiredView(for: providerId)
        } else if providerId == .gemini && (SettingsService.geminiPlan == nil || showingGeminiPlanSetup) {
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
        } else if providerId == .geminiConsumer && showingGeminiConsumerPlanSetup {
            GeminiConsumerPlanSetupView(
                currentPlan: SettingsService.geminiConsumerPlan,
                onConfirm: { plan in
                    SettingsService.geminiConsumerPlan = plan
                    showingGeminiConsumerPlanSetup = false
                    viewModel.refresh()
                },
                onCancel: { showingGeminiConsumerPlanSetup = false }
            )
        } else if !providerId.supportsUsageTracking {
            comingSoonView(for: providerId)
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
            CircularSpinner(size: 24, lineWidth: 3)
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
                // ── Providers ── (provider management, surfaced first)
                sectionLabel("Providers")

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

                // Full uninstall for non-Terminal users: cleans up the login item,
                // browser manifests, app-group container, caches, prefs, and our
                // Keychain items, then moves the app to the Trash and quits.
                // Styled like every other row (no red) so it doesn't draw the eye;
                // sits above Quit so the bottom-most tap target stays harmless.
                Button {
                    showingUninstallConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .scaledFont(.caption)
                            .frame(width: 16 * textSize.iconScale, height: 16 * textSize.iconScale)
                            .foregroundStyle(.secondary)
                        Text("Uninstall Tokenomics…")
                            .scaledFont(.caption)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .alert("Uninstall Tokenomics?", isPresented: $showingUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                UninstallService.uninstallAndQuit()
            }
        } message: {
            Text("This removes Tokenomics and all its settings from your Mac, then moves the app to the Trash. Your AI tools (Claude Code, Cursor, etc.) are not affected. This can't be undone.")
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

    // MARK: - Detection Nudge Banner

    /// Slim, dismissible banner shown atop the usage view when we detect AI tools
    /// on the machine the user hasn't added yet. Non-blocking by design — the user
    /// already has providers connected, so we never cover their usage. Tapping
    /// "Add" opens the persistent guided-setup window.
    private var detectionNudgeBanner: some View {
        let names = viewModel.detectedNotConnected.map { $0.displayName }
        let message: String
        switch names.count {
        case 1:  message = "Found \(names[0]) — not tracked yet."
        case 2:  message = "Found \(names[0]) and \(names[1]) — not tracked yet."
        default: message = "Found \(names[0]) and \(names.count - 1) more — not tracked yet."
        }

        return HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.Color.brand600)

            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Tokens.DynamicColor.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button("Add →") {
                openWindow(id: "onboarding")
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Tokens.Color.brand600)
            .buttonStyle(.plain)

            Button {
                dismissedDetectionNudge = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Tokens.DynamicColor.textSubtle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Tokens.Color.brand600.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
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
