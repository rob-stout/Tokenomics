import SwiftUI
import Combine

/// Main view model orchestrating multiple AI usage providers
@MainActor
final class UsageViewModel: ObservableObject {

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

    /// Navigation state
    @Published var showSettings = false
    @Published var showAIConnections = false
    @Published var showAbout = false
    @Published var showHowItWorks = false
    @Published var showNotifications = false

    // MARK: - Providers

    private let providers: [ProviderId: any UsageProvider] = [
        .claude: ClaudeProvider(),
        .copilot: CopilotProvider(),
        .cursor: CursorProvider(),
        .codex: CodexProvider(),
        .gemini: GeminiProvider()
    ]

    private let pollingService = PollingService()
    private var activityMonitor: ActivityMonitor?
    let notificationService = NotificationService()

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
        for id in ProviderId.allCases {
            if let cached = SettingsService.cachedUsage(for: id) {
                providerStates[id] = ProviderState(
                    connection: .notInstalled,
                    usage: cached.snapshot,
                    error: nil,
                    lastSynced: cached.cachedAt,
                    isLoading: false
                )
            }
        }
    }

    // MARK: - Lifecycle

    func startPolling() {
        Task {
            // Initial detection
            await detectProviders()

            // Auto-complete onboarding for existing users who already have Claude
            if !hasCompletedOnboarding {
                let claudeConnected = providerStates[.claude]?.connection.isConnected == true
                if claudeConnected {
                    completeOnboarding()
                }
            }

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
        Task {
            // Manual refresh counts as activity — resets idle timer
            await pollingService.noteActivity()
            // Fetch all providers and reset their poll timers
            for (id, _) in providerPairs {
                await pollingService.markFetched(id)
            }
            await fetchAllProviders()
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        SettingsService.hasCompletedOnboarding = true

        // Auto-select first connected provider
        if selectedTab == nil {
            selectedTab = visibleProviders.first ?? .claude
        }
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

    // MARK: - Popover Lifecycle

    /// Resets navigation to the home/usage view
    func resetNavigation() {
        showSettings = false
        showAIConnections = false
        showAbout = false
        showHowItWorks = false
        showNotifications = false
    }

    // MARK: - Private

    /// Stable iteration order so detection/fetching is deterministic
    private var providerPairs: [(ProviderId, any UsageProvider)] {
        ProviderId.allCases.compactMap { id in
            providers[id].map { (id, $0) }
        }
    }

    private func detectProviders() async {
        for (id, provider) in providerPairs {
            let connection = await provider.checkConnection()
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

    /// Re-checks only non-connected providers (called when popover opens)
    func redetectProviders() {
        Task {
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
        let newState = await fetchSingleProvider(
            id: id, provider: provider, currentState: currentState
        )
        providerStates[id] = newState
        pushToWidgets()
    }

    /// Fetch all providers concurrently (used by manual refresh)
    private func fetchAllProviders() async {
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
}
