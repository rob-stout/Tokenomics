import SwiftUI
import Combine

/// Main view model orchestrating multiple AI usage providers
@MainActor
final class UsageViewModel: ObservableObject {

    // MARK: - Bridge services (injected from AppDelegate)
    //
    // UsageViewModel doesn't own these — AppDelegate does. We hold a weak reference
    // via a setter called once at startup so the VM can push snapshots and commands
    // without needing to reach back through the app delegate at call sites.

    /// Set once by the app entry point after AppDelegate is ready.
    var macSideStateExporter: MacSideStateExporter?

    /// Notification observers for bridge wiring. Retained so they're cancelled on deinit.
    private var bridgeObservers: [Any] = []

    // MARK: - Published State

    /// Per-provider state (connection, usage, errors)
    @Published private(set) var providerStates: [ProviderId: ProviderState] = [:]

    /// Currently selected tab
    @Published var selectedTab: ProviderId? {
        didSet { SettingsService.selectedTab = selectedTab }
    }

    /// Providers pinned to show individual rings in menu bar
    @Published var pinnedProviders: Set<ProviderId> = [] {
        didSet { SettingsService.pinnedProviders = pinnedProviders }
    }

    /// Custom provider display order
    @Published var providerOrder: [ProviderId] = [] {
        didSet { SettingsService.providerOrder = providerOrder }
    }

    /// Providers hidden from the tab bar
    @Published var hiddenProviders: Set<ProviderId> = [] {
        didSet { SettingsService.hiddenProviders = hiddenProviders }
    }

    /// Whether onboarding has been completed
    @Published private(set) var hasCompletedOnboarding: Bool

    /// Two-way bound to the MenuBarExtra popover's presentation (via
    /// MenuBarExtraAccess). Set true to open the popover programmatically — e.g.
    /// at the end of onboarding so the user lands on their usage.
    @Published var isPopoverPresented = false

    /// Navigation state
    @Published var showSettings = false
    @Published var showAIConnections = false
    @Published var showAbout = false
    @Published var showHowItWorks = false
    @Published var showNotifications = false
    @Published var showTextSize = false

    /// API key entry sheet — lifted here so resetNavigation can guard against
    /// dismissing AIConnectionsView while the sheet is open (the sheet window
    /// takes key focus, which would otherwise fire didResignKeyNotification and
    /// tear down the parent view before the sheet renders).
    @Published var apiKeyEntryProvider: ProviderId?

    /// Copilot PAT entry sheet — promoted from AIConnectionsView's local @State
    /// so the new connector flow can trigger it from outside that view.
    @Published var copilotPATEntryRequested: Bool = false

    // MARK: - Demo Mode

    /// When `true`, the VM serves fixture data instead of polling live APIs.
    /// Backed by UserDefaults so it persists across launches (useful for continuous
    /// review sessions). Only settable when `BuildInfo.showsDebugTools` is true —
    /// stable release builds can never activate demo mode.
    @Published var demoModeEnabled: Bool = false {
        didSet {
            guard BuildInfo.showsDebugTools else {
                // Safety net: silently revert if somehow called in a stable build.
                demoModeEnabled = false
                return
            }
            UserDefaults.standard.set(demoModeEnabled, forKey: DemoModeService.userDefaultsKey)
            if demoModeEnabled {
                applyDemoData(snapshots: DemoData.allSnapshots)
            }
            // When turning off, re-start normal polling so live data replaces fixture data.
            if !demoModeEnabled && pollingStarted {
                Task { await fetchAllProviders() }
            }
        }
    }

    // MARK: - Providers

    private let providers: [ProviderId: any UsageProvider] = [
        .claude: ClaudeProvider(),
        .copilot: CopilotProvider(),
        .cursor: CursorProvider(),
        .codex: CodexProvider(),
        .gemini: GeminiProvider(),
        .elevenlabs: ElevenLabsProvider(),
        .runway: RunwayProvider(),
        .stableDiffusion: StableDiffusionProvider()
        // .midjourney, .suno, .udio have no API — omitted intentionally
    ]

    private let pollingService = PollingService()
    private var activityMonitor: ActivityMonitor?

    /// Polling is gated behind onboarding completion so first-launch users don't
    /// hit keychain / cross-app TCC prompts before the guided flow can explain
    /// them. Flipped true the first time `startPolling()` actually runs.
    private var pollingStarted = false
    let notificationService = NotificationService()

    private var isDetecting = false

    // MARK: - Computed Properties

    /// Providers that are connected (have usage data or are connected)
    var connectedProviders: [ProviderId] {
        orderedProviders.filter { id in
            guard let state = providerStates[id] else { return false }
            return state.connection.isConnected
        }
    }

    /// Providers that are at least installed (not .notInstalled)
    var installedProviders: [ProviderId] {
        orderedProviders.filter { id in
            guard let state = providerStates[id] else { return false }
            return state.connection != .notInstalled
        }
    }

    /// Providers detected on the machine but not yet added to Tokenomics
    /// (installed, no auth). Drives the non-blocking "we found X" nudge banner
    /// shown atop the usage view once at least one provider is connected.
    var detectedNotConnected: [ProviderId] {
        Self.detectedNotConnectedProviders(
            connections: providerStates.mapValues { $0.connection },
            order: orderedProviders
        )
    }

    /// Pure helper for `detectedNotConnected`: providers in the `.installedNoAuth`
    /// state, in the given order. Detected on disk but never connected to us.
    /// Static so it can be unit-tested without a live view model.
    static func detectedNotConnectedProviders(
        connections: [ProviderId: ProviderConnectionState],
        order: [ProviderId]
    ) -> [ProviderId] {
        order.filter { id in
            if case .installedNoAuth = connections[id] { return true }
            return false
        }
    }

    /// Pure helper: whether the non-blocking detection nudge should show. It's a
    /// nudge, not a wall — only once something is already connected (so we never
    /// cover the empty-state takeover), only when there's something to add, and
    /// not after the user dismissed it this session.
    static func showsDetectionNudge(
        dismissed: Bool,
        connectedCount: Int,
        detectedCount: Int
    ) -> Bool {
        !dismissed && connectedCount > 0 && detectedCount > 0
    }

    /// All providers in display order (custom order with fallback to enum order)
    var orderedProviders: [ProviderId] {
        if providerOrder.isEmpty {
            return ProviderId.allCases.map { $0 }
        }
        // Start with custom order, append any new providers not yet in the list
        var result = providerOrder.filter { ProviderId.allCases.contains($0) }
        for id in ProviderId.allCases where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    /// Providers to show as tabs (connected, not hidden, in custom order)
    var visibleProviders: [ProviderId] {
        orderedProviders.filter { id in
            guard !hiddenProviders.contains(id) else { return false }
            guard let state = providerStates[id] else { return false }
            switch state.connection {
            case .connected, .authExpired, .unavailable:
                return true
            case .notInstalled, .installedNoAuth:
                return false
            }
        }
    }

    /// Whether we need tabs (more than one visible provider)
    var showTabs: Bool {
        visibleProviders.count > 1
    }

    // MARK: - Brand-level accessors (Phase 5.6 foundation)
    //
    // These helpers group `visibleProviders` by `BrandId` for the brand-aware
    // popover / widget / Pin Tracker surfaces. They live alongside the
    // existing per-ProviderId accessors — both shapes are exposed so the new
    // rendering paths can opt in behind `FeatureFlags.brandAggregation` while
    // the legacy paths keep working unchanged.

    /// Brands that have at least one visible provider, in the order their
    /// first-visible provider appears. Stable for tab ordering.
    var enabledBrands: [BrandId] {
        Self.brandList(from: visibleProviders)
    }

    /// Returns the visible `ProviderState`s for the given brand's pools, in
    /// the same order they appear in `visibleProviders`. Multi-pool brands
    /// return 2+ states; single-pool brands return 1 (or 0 if the brand has
    /// no visible providers).
    func pools(for brand: BrandId) -> [ProviderState] {
        Self.providers(in: brand, from: visibleProviders)
            .compactMap { providerStates[$0] }
    }

    /// Returns `(ProviderId, ProviderState)` pairs for the given brand's visible pools,
    /// ordered by `visibleProviders`. The tab body needs both the id (for routing
    /// Gemini plan setup, auth-expired labels, etc.) and the state.
    func poolPairs(for brand: BrandId) -> [(ProviderId, ProviderState)] {
        Self.providers(in: brand, from: visibleProviders)
            .compactMap { id in
                providerStates[id].map { (id, $0) }
            }
    }

    /// Pure helper: collapses a provider list into the unique brands that
    /// own them, preserving the order each brand first appears. Separated
    /// from `enabledBrands` so it can be exercised in tests without standing
    /// up a full view model (whose `providerStates` is private-set).
    static func brandList(from providers: [ProviderId]) -> [BrandId] {
        var seen = Set<BrandId>()
        var result: [BrandId] = []
        for providerId in providers {
            let brand = providerId.brand
            if seen.insert(brand).inserted {
                result.append(brand)
            }
        }
        return result
    }

    /// Pure helper: filters a provider list to those owned by the given brand,
    /// preserving order. Companion to `brandList(from:)`.
    static func providers(in brand: BrandId, from providers: [ProviderId]) -> [ProviderId] {
        providers.filter { $0.brand == brand }
    }

    /// State for the currently selected provider
    var currentProviderState: ProviderState? {
        guard let tab = selectedTab else { return nil }
        return providerStates[tab]
    }

    /// Usage state for menu bar icon rendering
    var menuBarState: UsageState {
        if visibleProviders.isEmpty {
            // Check if any provider has a token
            let hasAnyAuth = providerStates.values.contains { state in
                switch state.connection {
                case .connected, .authExpired:
                    return true
                default:
                    return false
                }
            }
            return hasAnyAuth ? .error : .unauthenticated
        }

        // Use the worst (highest) utilization across connected providers
        guard let worstUsage = worstOfNUsage() else {
            return .loading
        }
        return UsageState(utilization: worstUsage.shortWindow.utilization)
    }

    /// Menu bar data for Smart mode (worst-of-N), respects visibility settings
    func worstOfNUsage() -> ProviderUsageSnapshot? {
        visibleProviders
            .compactMap { providerStates[$0]?.usage }
            .max(by: { $0.shortWindow.utilization < $1.shortWindow.utilization })
    }

    /// Menu bar ring data for a specific provider.
    /// Returns nil when no usage is available. `sevenDay` and `sevenDayPace` are nil
    /// when the provider only exposes a single usage window.
    func menuBarRingData(for providerId: ProviderId) -> (fiveHour: Double, sevenDay: Double?, fiveHourPace: Double, sevenDayPace: Double?)? {
        guard let usage = providerStates[providerId]?.usage else { return nil }
        return (
            fiveHour: usage.shortWindow.utilization,
            sevenDay: usage.longWindow?.utilization,
            fiveHourPace: usage.shortWindow.pace,
            sevenDayPace: usage.longWindow?.pace
        )
    }

    /// Tooltip text for the menu bar — shows both windows per provider when available
    var menuBarTooltip: String {
        let parts = visibleProviders.compactMap { id -> String? in
            guard let usage = providerStates[id]?.usage else { return nil }
            if let longWindow = usage.longWindow {
                return "\(id.displayName): 5hr \(Int(usage.shortWindow.utilization))% | 7day \(Int(longWindow.utilization))%"
            } else {
                return "\(id.displayName): \(Int(usage.shortWindow.utilization))%"
            }
        }
        guard !parts.isEmpty else { return "Tokenomics" }
        return parts.joined(separator: "\n")
    }

    /// Overall sync text (uses the most recent sync time across providers)
    var lastSynced: Date? {
        providerStates.values
            .compactMap(\.lastSynced)
            .max()
    }

    /// Whether any provider is currently loading
    var isLoading: Bool {
        providerStates.values.contains(where: \.isLoading)
    }

    /// Whether the current provider is rate-limited but showing cached data
    var isShowingStaleData: Bool {
        guard let tab = selectedTab,
              let state = providerStates[tab] else { return false }
        if case .rateLimited = state.error {
            return state.usage != nil
        }
        return false
    }

    /// Plan label for the current tab
    var planLabel: String {
        currentProviderState?.usage?.planLabel ?? "—"
    }

    /// Whether we have at least one authenticated provider
    var isAuthenticated: Bool {
        !connectedProviders.isEmpty
    }

    // MARK: - Init

    init() {
        self.hasCompletedOnboarding = SettingsService.hasCompletedOnboarding
        self.pinnedProviders = SettingsService.pinnedProviders
        self.providerOrder = SettingsService.providerOrder
        self.hiddenProviders = SettingsService.hiddenProviders
        self.selectedTab = SettingsService.selectedTab

        // Pre-populate provider states with cached usage so data shows instantly
        var hasAnyCached = false
        for id in ProviderId.allCases {
            if let cached = SettingsService.cachedUsage(for: id) {
                hasAnyCached = true
                providerStates[id] = ProviderState(
                    connection: .notInstalled,
                    usage: cached.snapshot,
                    error: nil,
                    lastSynced: cached.cachedAt,
                    isLoading: false
                )
            }
        }

        // Migration: pre-onboarding-flow versions never set hasCompletedOnboarding.
        // Treat any user with cached usage as already onboarded so the upgrade
        // doesn't shove them through Welcome on launch.
        if !self.hasCompletedOnboarding && hasAnyCached {
            self.hasCompletedOnboarding = true
            SettingsService.hasCompletedOnboarding = true
        }

        // Restore demo mode from UserDefaults — only honoured in debug/beta builds.
        if BuildInfo.showsDebugTools {
            let saved = UserDefaults.standard.bool(forKey: DemoModeService.userDefaultsKey)
            if saved {
                self.demoModeEnabled = true
                applyDemoData(snapshots: DemoData.allSnapshots)
            }
        }
    }

    // MARK: - Lifecycle

    func startPolling() {
        // Demo mode bypasses all live polling — fixture data is already in providerStates.
        guard !demoModeEnabled else { return }

        // Don't run detection until the user has been through onboarding. The
        // guided flow's PermissionsStep is responsible for triggering the
        // keychain / cross-app prompts at a known UI moment; running
        // detectProviders() here would race the window and fire prompts blind.
        guard hasCompletedOnboarding else { return }

        // Idempotent: callers (MenuBarLabel.onAppear and completeOnboarding)
        // can both invoke this without spinning up duplicate polling loops.
        guard !pollingStarted else { return }
        pollingStarted = true

        // Wire bridge notification observers once polling starts. This is the
        // earliest point where the app delegate's services are fully initialized.
        registerBridgeObservers()

        Task {
            // Initial detection
            await detectProviders()

            // Set initial tab if needed
            if selectedTab == nil || !visibleProviders.contains(selectedTab ?? .claude) {
                selectedTab = visibleProviders.first ?? .claude
            }

            // Register each provider's poll interval
            for (id, provider) in providerPairs {
                let interval = await provider.pollInterval
                await pollingService.registerProvider(id, interval: interval)
            }

            // Start per-provider polling loop
            await pollingService.start { [weak self] providerId in
                await self?.fetchProvider(providerId)
            }

            // Watch ~/.claude for activity to sleep/wake polling
            startActivityMonitor()
        }
    }

    /// Registers NotificationCenter observers that wire the bridge layer into
    /// the VM without creating a retain cycle. Safe to call once; calling more
    /// than once is a no-op because `pollingStarted` guards the caller.
    private func registerBridgeObservers() {
        // Extension requests a native re-poll → treat it the same as a user tapping Refresh.
        let refreshObserver = NotificationCenter.default.addObserver(
            forName: .tokenomicsBridgeRefreshRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        // SettingsService.setVisibility was called → propagate to MacSideStateExporter.
        let visibilityObserver = NotificationCenter.default.addObserver(
            forName: .tokenomicsProviderVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let providerIdRaw = note.object as? String,
                  let setting = note.userInfo?["setting"] as? ProviderVisibilitySetting,
                  let exporter = self.macSideStateExporter else { return }
            Task {
                await exporter.setVisibility(setting, for: providerIdRaw)
            }
        }

        bridgeObservers = [refreshObserver, visibilityObserver]
    }

    private func startActivityMonitor() {
        activityMonitor = ActivityMonitor { [weak self] in
            guard let self else { return }
            Task {
                await self.pollingService.noteActivity()
            }
        }
        activityMonitor?.start()
    }

    func stopPolling() {
        activityMonitor?.stop()
        activityMonitor = nil
        Task { await pollingService.stop() }
    }

    func refresh() {
        // In demo mode, re-apply fixture data so the UI updates (e.g. after slam).
        guard !demoModeEnabled else {
            applyDemoData(snapshots: DemoData.allSnapshots)
            return
        }
        Task {
            // Manual refresh counts as activity — resets idle timer
            await pollingService.noteActivity()
            // Fetch all providers and reset their poll timers
            for (id, _) in providerPairs {
                await pollingService.markFetched(id)
            }
            await fetchAllProviders()

            // Tell the extension to re-poll its web-fetched providers on its
            // next heartbeat (~60s). Fire-and-forget — native refresh is already done.
            if let exporter = macSideStateExporter {
                await exporter.enqueueCommand(BridgeCommand(kind: "refreshWebProviders"))
            }
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        SettingsService.hasCompletedOnboarding = true

        // Auto-select first connected provider
        if selectedTab == nil {
            selectedTab = visibleProviders.first ?? .claude
        }

        // Polling was gated behind onboarding — kick it off now that the user
        // has consented via the PermissionsStep. No-op if already running.
        startPolling()
    }

    // MARK: - Provider Pin Management

    func togglePin(for provider: ProviderId) {
        if pinnedProviders.contains(provider) {
            // Unpin → back to smart mode
            pinnedProviders.removeAll()
        } else {
            // Pin this one exclusively (radio behavior)
            pinnedProviders = [provider]
        }
    }

    func isPinned(_ provider: ProviderId) -> Bool {
        pinnedProviders.contains(provider)
    }

    var isSmartMode: Bool {
        pinnedProviders.isEmpty
    }

    func setSmartMode() {
        pinnedProviders.removeAll()
    }

    // MARK: - Provider Visibility

    func isHidden(_ provider: ProviderId) -> Bool {
        hiddenProviders.contains(provider)
    }

    func toggleVisibility(for provider: ProviderId) {
        if hiddenProviders.contains(provider) {
            hiddenProviders.remove(provider)
        } else {
            hiddenProviders.insert(provider)
        }
        // If we hid a pinned provider, revert to smart mode
        if pinnedProviders.contains(provider) && hiddenProviders.contains(provider) {
            pinnedProviders.removeAll()
        }
        // If we hid the selected tab, move to another
        if let tab = selectedTab, hiddenProviders.contains(tab) {
            selectedTab = visibleProviders.first
        }
    }

    func swapProviders(_ from: ProviderId, _ to: ProviderId) {
        var order = orderedProviders
        guard let fromIndex = order.firstIndex(of: from),
              let toIndex = order.firstIndex(of: to) else { return }
        order.swapAt(fromIndex, toIndex)
        providerOrder = order
    }

    func moveProvider(_ provider: ProviderId, toIndex: Int) {
        var order = orderedProviders
        guard let fromIndex = order.firstIndex(of: provider),
              fromIndex != toIndex,
              order.indices.contains(toIndex) else { return }
        let item = order.remove(at: fromIndex)
        order.insert(item, at: toIndex)
        providerOrder = order
    }

    /// Reorders brand tabs (brand-aggregation popover) by moving a brand's whole
    /// pool block to a new position among the visible brand tabs.
    ///
    /// Brand order is *derived* from `providerOrder` (via `enabledBrands`), so
    /// there's no separate brand-order store: we rebuild `providerOrder` with the
    /// brand's providers relocated as a contiguous block. Hidden providers keep
    /// their relative order at the tail.
    func moveBrand(_ brand: BrandId, toIndex: Int) {
        guard let newOrder = Self.reorderedProviderOrder(
            movingBrand: brand,
            toVisibleIndex: toIndex,
            visibleBrands: enabledBrands,
            order: orderedProviders
        ) else { return }
        providerOrder = newOrder
    }

    /// Pure helper for `moveBrand`: produces a new provider order with `brand`
    /// moved to `toIndex` within the visible brand sequence, rebuilt as
    /// brand-contiguous blocks. Returns nil for no-ops / invalid indices.
    ///
    /// Separated as a static so it can be unit-tested without a live view model.
    static func reorderedProviderOrder(
        movingBrand brand: BrandId,
        toVisibleIndex toIndex: Int,
        visibleBrands: [BrandId],
        order: [ProviderId]
    ) -> [ProviderId]? {
        var seq = visibleBrands
        guard let fromIndex = seq.firstIndex(of: brand),
              fromIndex != toIndex,
              seq.indices.contains(toIndex) else { return nil }
        let moved = seq.remove(at: fromIndex)
        seq.insert(moved, at: toIndex)

        // Full brand order: reordered visible brands first, then any brands not
        // visible (hidden) in their existing relative order.
        let existingBrandOrder = brandList(from: order)
        let tail = existingBrandOrder.filter { !seq.contains($0) }
        let fullBrandOrder = seq + tail

        // Rebuild provider order as brand-contiguous blocks, preserving each
        // brand's internal provider order.
        var newOrder: [ProviderId] = []
        for b in fullBrandOrder {
            newOrder.append(contentsOf: order.filter { $0.brand == b })
        }
        // Safety net: append any provider somehow not yet emitted.
        for id in order where !newOrder.contains(id) {
            newOrder.append(id)
        }
        return newOrder
    }

    // MARK: - Popover Lifecycle

    /// Selects the most contextually relevant tab when the popover opens.
    /// Priority: pinned provider → worst-of-N (smart mode) → last selected tab.
    func selectContextualTab() {
        if let pinned = pinnedProviders.first, visibleProviders.contains(pinned) {
            selectedTab = pinned
        } else if pinnedProviders.isEmpty, let worst = worstOfNUsage(),
                  let worstId = visibleProviders.first(where: { providerStates[$0]?.usage?.shortWindow.utilization == worst.shortWindow.utilization }) {
            selectedTab = worstId
        }
        // Otherwise keep the persisted selectedTab as-is
    }

    /// Resets navigation to the home/usage view.
    /// Skips dismissing AIConnectionsView when the API key entry sheet is open —
    /// the sheet window takes key focus, firing didResignKeyNotification, and we
    /// must not destroy the parent view before the sheet can present.
    func resetNavigation() {
        showSettings = false
        if apiKeyEntryProvider == nil {
            showAIConnections = false
        }
        showAbout = false
        showHowItWorks = false
        showNotifications = false
        showTextSize = false
    }

    // MARK: - Private

    /// Stable iteration order so detection/fetching is deterministic
    private var providerPairs: [(ProviderId, any UsageProvider)] {
        ProviderId.allCases.compactMap { id in
            providers[id].map { (id, $0) }
        }
    }

    private func detectProviders() async {
        for id in ProviderId.allCases {
            if let provider = providers[id] {
                let connection = await provider.checkConnection()
                let existing = providerStates[id] ?? .empty
                providerStates[id] = ProviderState(
                    connection: connection,
                    usage: existing.usage,
                    error: existing.error,
                    lastSynced: existing.lastSynced,
                    isLoading: false
                )
            } else {
                // Placeholder provider — no API implementation yet
                providerStates[id] = providerStates[id] ?? .empty
            }
        }
    }

    /// Re-checks only non-connected providers (called when popover opens or after connecting a provider)
    func redetectProviders() {
        guard !isDetecting else { return }
        isDetecting = true
        Task {
            defer { isDetecting = false }
            for (id, provider) in providerPairs {
                let current = providerStates[id]?.connection ?? .notInstalled
                // Skip already-connected providers — no need to re-check
                guard !current.isConnected else { continue }

                let connection = await provider.checkConnection()
                if connection != current {
                    let existing = providerStates[id] ?? .empty
                    providerStates[id] = ProviderState(
                        connection: connection,
                        usage: existing.usage,
                        error: existing.error,
                        lastSynced: existing.lastSynced,
                        isLoading: false
                    )
                }
            }

            // Update selected tab if needed
            if selectedTab == nil || !visibleProviders.contains(selectedTab ?? .claude) {
                selectedTab = visibleProviders.first ?? .claude
            }
        }
    }

    /// Fetch a single provider by ID (called by the per-provider polling loop)
    private func fetchProvider(_ id: ProviderId) async {
        guard let provider = providers[id] else { return }
        let currentState = providerStates[id] ?? .empty
        if currentState.connection.isConnected {
            providerStates[id] = ProviderState(
                connection: currentState.connection,
                usage: currentState.usage,
                error: currentState.error,
                lastSynced: currentState.lastSynced,
                isLoading: true
            )
        }
        let newState = await fetchSingleProvider(
            id: id, provider: provider, currentState: currentState
        )
        providerStates[id] = newState
        pushToWidgets()
    }

    /// Fetch all providers concurrently (used by manual refresh)
    private func fetchAllProviders() async {
        for (id, _) in providerPairs {
            let currentState = providerStates[id] ?? .empty
            if currentState.connection.isConnected {
                providerStates[id] = ProviderState(
                    connection: currentState.connection,
                    usage: currentState.usage,
                    error: currentState.error,
                    lastSynced: currentState.lastSynced,
                    isLoading: true
                )
            }
        }
        await withTaskGroup(of: (ProviderId, ProviderState).self) { group in
            for (id, provider) in providerPairs {
                let currentState = providerStates[id] ?? .empty
                group.addTask {
                    let newState = await self.fetchSingleProvider(
                        id: id, provider: provider, currentState: currentState
                    )
                    return (id, newState)
                }
            }

            for await (id, newState) in group {
                providerStates[id] = newState
            }
        }
        pushToWidgets()
    }

    // MARK: - Bridge Snapshot Conversion

    /// Converts a native `ProviderUsageSnapshot` into the wire-format `BridgeSnapshot`
    /// that MacSideStateExporter writes to mac-side.json.
    ///
    /// `WindowUsage.utilization` is 0–100 (percentage); `BridgeWindow.utilization` is
    /// 0–1 (fraction). The division normalises the value for the extension.
    private func makeBridgeSnapshot(from snapshot: ProviderUsageSnapshot, provider: ProviderId) -> BridgeSnapshot {
        func makeBridgeWindow(_ window: WindowUsage) -> BridgeWindow {
            BridgeWindow(
                label: window.label,
                utilization: window.utilization / 100.0,
                resetsAt: window.resetsAt,
                windowDurationSec: window.windowDuration,
                sublabelOverride: window.sublabelOverride
            )
        }

        return BridgeSnapshot(
            provider: provider.rawValue,
            capturedAt: Date(),
            estimated: nil,
            shortWindow: makeBridgeWindow(snapshot.shortWindow),
            longWindow: snapshot.longWindow.map { makeBridgeWindow($0) },
            planLabel: snapshot.planLabel
        )
    }

    // MARK: - Widget Push

    /// Push current usage data to the shared App Group store for WidgetKit.
    /// Uses visibleProviders so the widget respects the user's sort order and hidden providers.
    private func pushToWidgets() {
        let entries: [(ProviderId, ProviderUsageSnapshot)] = visibleProviders.compactMap { id in
            guard let usage = providerStates[id]?.usage else { return nil }
            return (id, usage)
        }
        guard !entries.isEmpty else { return }
        WidgetDataStore.write(providers: entries)
    }

    private func fetchSingleProvider(
        id: ProviderId,
        provider: any UsageProvider,
        currentState: ProviderState
    ) async -> ProviderState {
        // Skip providers that aren't connected — just re-check detection
        guard currentState.connection.isConnected else {
            let newConnection = await provider.checkConnection()
            if newConnection != currentState.connection {
                return ProviderState(
                    connection: newConnection,
                    usage: currentState.usage,
                    error: currentState.error,
                    lastSynced: currentState.lastSynced,
                    isLoading: false
                )
            }
            return currentState
        }

        do {
            let snapshot = try await provider.fetchUsage()
            SettingsService.cacheUsage(snapshot, for: id)
            // Evaluate thresholds after every successful fetch
            notificationService.evaluate(
                providerId: id,
                snapshot: snapshot,
                connection: currentState.connection
            )

            // Push a fresh bridge snapshot alongside the widget write.
            // chatgpt is web-companion-only; native pollers never produce it.
            if id != .chatgpt, let exporter = macSideStateExporter {
                let bridgeSnap = makeBridgeSnapshot(from: snapshot, provider: id)
                await exporter.setNativeSnapshot(bridgeSnap)
            }

            return ProviderState(
                connection: currentState.connection,
                usage: snapshot,
                error: nil,
                lastSynced: Date(),
                isLoading: false
            )
        } catch let error as AppError {
            if error.isTokenExpired {
                return ProviderState(
                    connection: .authExpired,
                    usage: nil,
                    error: error,
                    lastSynced: currentState.lastSynced,
                    isLoading: false
                )
            }
            return ProviderState(
                connection: currentState.connection,
                usage: currentState.usage,
                error: error,
                lastSynced: currentState.lastSynced,
                isLoading: false
            )
        } catch {
            return ProviderState(
                connection: currentState.connection,
                usage: currentState.usage,
                error: .unexpectedError(underlying: error),
                lastSynced: currentState.lastSynced,
                isLoading: false
            )
        }
    }

    // MARK: - Debug Helpers

    /// Resets onboarding state so the guided flow re-runs on next launch.
    /// Only callable from debug/beta builds via `DebugMenuView`.
    func resetOnboardingForDebug() {
        hasCompletedOnboarding = false
        pollingStarted = false
    }

    // MARK: - Demo Data

    /// Injects fixture snapshots for every known provider and writes them to
    /// the shared widget store so the menu-bar rings and widgets also reflect
    /// demo data. The `connected` state is synthesised so all providers appear
    /// as tabs — the demo is only meaningful when every UI surface is populated.
    ///
    /// Called from `demoModeEnabled.didSet` and `refresh()` while demo mode is on.
    /// Applies fixture data for demo mode. When `fireNotifications` is true, each
    /// connected provider is run through `notificationService.evaluate` exactly as
    /// the live fetch path does — so the slam buttons can be used to test threshold
    /// notifications (slam to 0% to reset the hysteresis, then to 90/100% to fire).
    /// Plain demo-on leaves it false so toggling demo mode doesn't spam alerts.
    func applyDemoData(snapshots: [ProviderId: ProviderUsageSnapshot], fireNotifications: Bool = false) {
        let now = Date()
        for id in ProviderId.allCases {
            if let snapshot = snapshots[id] {
                let connection: ProviderConnectionState = .connected(plan: snapshot.planLabel)
                providerStates[id] = ProviderState(
                    connection: connection,
                    usage: snapshot,
                    error: nil,
                    lastSynced: now,
                    isLoading: false
                )
                if fireNotifications {
                    notificationService.evaluate(providerId: id, snapshot: snapshot, connection: connection)
                }
            } else {
                // Provider has no demo snapshot (e.g. suno, udio) — mark not installed
                // so it doesn't show up as a blank tab.
                providerStates[id] = .empty
            }
        }

        // Ensure a tab is selected
        if selectedTab == nil || providerStates[selectedTab ?? .claude]?.connection.isConnected != true {
            selectedTab = visibleProviders.first ?? .claude
        }

        // Push demo data to the widget App Group so menu-bar rings and desktop
        // widgets render fixture values instead of stale/empty live data.
        let entries: [(ProviderId, ProviderUsageSnapshot)] = visibleProviders.compactMap { id in
            guard let usage = providerStates[id]?.usage else { return nil }
            return (id, usage)
        }
        if !entries.isEmpty {
            WidgetDataStore.write(providers: entries)
        }
    }
}
