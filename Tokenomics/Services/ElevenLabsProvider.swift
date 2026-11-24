import Foundation
import os

/// ElevenLabs usage provider — tracks monthly character quota via the subscription API.
///
/// Auth: API key stored in Keychain via APIKeyService.
///
/// Two possible data sources, never both (see `ElevenLabsSourceResolver`):
/// 1. The Mac app's own API key (always wins when one is configured).
/// 2. Otherwise, the browser extension's ElevenLabs reading arriving over the bridge
///    (`ext-side.json`) — from the user's elevenlabs.io sign-in or a key pasted into the
///    extension. Only numbers cross the bridge; the extension's key never does.
///
/// API: `GET https://api.elevenlabs.io/v1/user/subscription`
/// Response includes character_count, character_limit, next_character_count_reset_unix, tier.
actor ElevenLabsProvider: UsageProvider {
    let id = ProviderId.elevenlabs
    let pollInterval: TimeInterval = 300 // 5 min

    /// Where the numbers from the most recent successful `fetchUsage()` came from.
    /// UsageViewModel reads this to avoid echoing a bridge-sourced reading back to
    /// the extension as if it were native (mirrors the web-only-pool export guard).
    private(set) var lastSource: ElevenLabsSource = .none

    private let apiKeyReader: @Sendable () -> String?
    private let bridgeSnapshotReader: @Sendable () -> BridgeSnapshot?
    private let subscriptionFetcher: (@Sendable (String) async throws -> ElevenLabsSubscription)?
    private let now: @Sendable () -> Date

    /// All parameters default to production behaviour; tests inject fakes.
    init(
        apiKeyReader: @escaping @Sendable () -> String? = { APIKeyService.read(for: .elevenlabs) },
        bridgeSnapshotReader: @escaping @Sendable () -> BridgeSnapshot? = {
            WebCompanionService.readStateFromAppGroup()?.snapshots[ProviderId.elevenlabs.rawValue]
        },
        subscriptionFetcher: (@Sendable (String) async throws -> ElevenLabsSubscription)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.apiKeyReader = apiKeyReader
        self.bridgeSnapshotReader = bridgeSnapshotReader
        self.subscriptionFetcher = subscriptionFetcher
        self.now = now
    }

    /// True when no Mac API key is configured, i.e. the only possible source is the
    /// extension. The view model uses this to refresh ElevenLabs on bridge file changes
    /// without ever hitting the network on the file watcher's behalf.
    var isBridgeFed: Bool { apiKeyReader() == nil }

    private func resolveSource(apiKey: String?) -> ElevenLabsSource {
        ElevenLabsSourceResolver.resolve(
            nativeKeyConfigured: apiKey != nil,
            bridge: bridgeSnapshotReader(),
            now: now()
        )
    }

    private static let log = Logger(subsystem: "com.robstout.tokenomics", category: "ElevenLabsProvider")

    func checkConnection() async -> ProviderConnectionState {
        if let forced = DetectionScenario.current.forcedConnection { return forced }
        let apiKey = apiKeyReader()
        switch resolveSource(apiKey: apiKey) {
        case .bridge:
            if let snap = bridgeSnapshotReader() {
                return .connected(plan: snap.planLabel.isEmpty ? "Browser" : snap.planLabel)
            }
            return .notInstalled
        case .none:
            return .notInstalled // No API key and no fresh extension reading = not connected
        case .native:
            break
        }
        guard let apiKey else { return .notInstalled }
        do {
            let sub = try await fetchSubscription(apiKey: apiKey)
            return .connected(plan: sub.tierLabel)
        } catch {
            Self.log.warning("ElevenLabs connection check failed: \(error.localizedDescription)")
            return .installedNoAuth
        }
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let apiKey = apiKeyReader()
        switch resolveSource(apiKey: apiKey) {
        case .bridge:
            guard let snap = bridgeSnapshotReader() else { throw AppError.notAuthenticated }
            lastSource = .bridge
            return Self.mapBridgeSnapshot(snap, now: now())
        case .none:
            lastSource = .none
            throw AppError.notAuthenticated
        case .native:
            guard let apiKey else { throw AppError.notAuthenticated }
            let sub = try await fetchSubscription(apiKey: apiKey)
            lastSource = .native
            return mapToSnapshot(sub)
        }
    }

    // MARK: - API

    private func fetchSubscription(apiKey: String) async throws -> ElevenLabsSubscription {
        if let subscriptionFetcher { return try await subscriptionFetcher(apiKey) }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        do {
            return try JSONDecoder().decode(ElevenLabsSubscription.self, from: data)
        } catch {
            Self.log.error("ElevenLabs decode failed: \(error). Body: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            throw AppError.decodingFailed(underlying: error)
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401: throw AppError.tokenExpired
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            throw AppError.rateLimited(retryAfter: retryAfter)
        default:
            throw AppError.httpError(statusCode: http.statusCode)
        }
    }

    // MARK: - Helpers

    /// Returns the billing cycle duration. Uses 31 days to cover worst-case
    /// calendar months. Passes 0 when `resetsAt` is distantFuture (nil API
    /// field) so the pace dot hides honestly.
    static func cycleDuration(for resetsAt: Date) -> TimeInterval {
        resetsAt == Date.distantFuture ? 0 : 31 * 24 * 3600
    }

    // MARK: - Mapping

    /// The extension only knows a rounded percentage, so there's no "N / M characters"
    /// sublabel the way the native API reading has. Shared mapping lives in
    /// `WebCompanionProvider.map` (utilization 0...1 → 0...100).
    static func mapBridgeSnapshot(_ snap: BridgeSnapshot, now: Date = Date()) -> ProviderUsageSnapshot {
        WebCompanionProvider.map(snap, id: .elevenlabs, now: now)
    }

    private func mapToSnapshot(_ sub: ElevenLabsSubscription) -> ProviderUsageSnapshot {
        let used = sub.characterCount
        let limit = sub.characterLimit
        let utilization = limit > 0 ? Double(used) / Double(limit) * 100 : 0

        let resetsAt: Date
        if let resetUnix = sub.nextCharacterCountResetUnix {
            resetsAt = Date(timeIntervalSince1970: TimeInterval(resetUnix))
        } else {
            resetsAt = Date.distantFuture
        }

        let cycleDuration = Self.cycleDuration(for: resetsAt)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let usedStr = formatter.string(from: NSNumber(value: used)) ?? "\(used)"
        let limitStr = formatter.string(from: NSNumber(value: limit)) ?? "\(limit)"

        return ProviderUsageSnapshot(
            shortWindow: WindowUsage(
                label: "Characters",
                utilization: min(utilization, 999),
                resetsAt: resetsAt,
                windowDuration: cycleDuration,
                sublabelOverride: "\(usedStr) / \(limitStr) used"
            ),
            longWindow: nil,
            planLabel: sub.tierLabel,
            extraUsage: nil,
            creditsBalance: nil
        )
    }
}

// MARK: - Response Model

struct ElevenLabsSubscription: Decodable {
    let tier: String?
    let characterCount: Int
    let characterLimit: Int
    let nextCharacterCountResetUnix: Int?

    var tierLabel: String {
        guard let tier else { return "Free" }
        return tier.prefix(1).uppercased() + tier.dropFirst()
    }

    enum CodingKeys: String, CodingKey {
        case tier
        case characterCount = "character_count"
        case characterLimit = "character_limit"
        case nextCharacterCountResetUnix = "next_character_count_reset_unix"
    }
}

// MARK: - Source selection

/// Which reading feeds the ElevenLabs card.
enum ElevenLabsSource: Equatable, Sendable {
    /// The Mac app's own API key.
    case native
    /// The browser extension's reading, relayed over the bridge.
    case bridge
    /// Neither — ElevenLabs is not connected.
    case none
}

/// Pure source-selection rule — exactly one source ever feeds ElevenLabs.
///
/// Rule: if an API key is *configured* in the Mac app, native wins outright — even if
/// the key is currently failing (revoked, offline). We key off "configured" rather than
/// "producing data" so the card never flips between two sources on a transient network
/// error, and a broken key surfaces as the usual re-auth prompt instead of silently
/// changing numbers. With no key, a usable bridge reading is used (see `WebPoolFreshness`:
/// live, or last-known and not yet expired); an expired or missing one means not connected.
enum ElevenLabsSourceResolver {
    static func resolve(nativeKeyConfigured: Bool, bridge: BridgeSnapshot?, now: Date = Date()) -> ElevenLabsSource {
        if nativeKeyConfigured { return .native }
        // Same rule as every other web pool: a live reading, or a last-known one that
        // hasn't passed its reset / retention limit (`WebPoolFreshness`).
        guard let bridge, WebPoolFreshness.isUsable(bridge, id: .elevenlabs, now: now) else { return .none }
        return .bridge
    }
}
