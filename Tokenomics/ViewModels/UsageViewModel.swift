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

    /// Whether onboarding has been completed
    @Published private(set) var hasCompletedOnboarding: Bool

    /// Navigation state
    @Published var showSettings = false
    @Published var showAIConnections = false
    @Published var showAbout = false

    // MARK: - Providers

    private let providers: [ProviderId: any UsageProvider] = [
        .claude: ClaudeProvider(),
        .codex: CodexProvider()
    ]

    private let pollingService = PollingService()

    // MARK: - Computed Properties

    /// Providers that are connected (have usage data or are connected)
    var connectedProviders: [ProviderId] {
        ProviderId.allCases.filter { id in
            guard let state = providerStates[id] else { return false }
            return state.connection.isConnected
        }
    }

    /// Providers to show as tabs (connected ones, in stable order)
    var visibleProviders: [ProviderId] {
        ProviderId.allCases.filter { id in
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
        if connectedProviders.isEmpty {
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

    /// Menu bar data for Smart mode (worst-of-N)
    func worstOfNUsage() -> ProviderUsageSnapshot? {
        connectedProviders
            .compactMap { providerStates[$0]?.usage }
            .max(by: { $0.shortWindow.utilization < $1.shortWindow.utilization })
    }

    /// Menu bar ring data for a specific provider
    func menuBarRingData(for providerId: ProviderId) -> (fiveHour: Double, sevenDay: Double, fiveHourPace: Double, sevenDayPace: Double)? {
        guard let usage = providerStates[providerId]?.usage else { return nil }
        return (
            fiveHour: usage.shortWindow.utilization,
            sevenDay: usage.longWindow.utilization,
            fiveHourPace: usage.shortWindow.pace,
            sevenDayPace: usage.longWindow.pace
        )
    }

    /// Tooltip text for the menu bar — shows both windows per provider
    var menuBarTooltip: String {
        let parts = connectedProviders.compactMap { id -> String? in
            guard let usage = providerStates[id]?.usage else { return nil }
            return "\(id.displayName): 5hr \(Int(usage.shortWindow.utilization))% | 7day \(Int(usage.longWindow.utilization))%"
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
        self.selectedTab = SettingsService.selectedTab
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

            // Start polling loop
            await pollingService.start { [weak self] in
                await self?.fetchAllProviders()
            }
        }
    }

    func stopPolling() {
        Task { await pollingService.stop() }
    }

    func refresh() {
        Task {
            await fetchAllProviders()

            // Restart polling if it was stopped
            let stopped = await !pollingService.isRunning
            if stopped {
                await pollingService.start { [weak self] in
                    await self?.fetchAllProviders()
                }
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
    }

    // MARK: - Provider Pin Management

    func togglePin(for provider: ProviderId) {
        if pinnedProviders.contains(provider) {
            pinnedProviders.remove(provider)
        } else {
            pinnedProviders.insert(provider)
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

    // MARK: - Private

    /// Stable iteration order so detection/fetching is deterministic
    private var providerOrder: [(ProviderId, any UsageProvider)] {
        ProviderId.allCases.compactMap { id in
            providers[id].map { (id, $0) }
        }
    }

    private func detectProviders() async {
        for (id, provider) in providerOrder {
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

        // Add Gemini as not-installed placeholder
        if providerStates[.gemini] == nil {
            providerStates[.gemini] = ProviderState(
                connection: .notInstalled,
                usage: nil,
                error: nil,
                lastSynced: nil,
                isLoading: false
            )
        }
    }

    private func fetchAllProviders() async {
        // Fetch all providers concurrently — Codex reads local files instantly
        // while Claude may be waiting on the network. They shouldn't block each other.
        await withTaskGroup(of: (ProviderId, ProviderState).self) { group in
            for (id, provider) in providerOrder {
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
