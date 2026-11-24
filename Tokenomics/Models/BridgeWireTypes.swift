import Foundation

// MARK: - Top-level envelopes

/// Request envelope sent from the browser extension to the TokenomicsBridge native host.
struct BridgeRequest: Codable, Sendable {
    let schemaVersion: Int
    let envelopeSentAt: Date
    let extensionId: String
    let snapshots: [BridgeSnapshot]
    let settings: BridgeSettings?
    let requestedActions: BridgeRequestedActions?
}

/// Response envelope written by the TokenomicsBridge host back to the extension.
struct BridgeResponse: Codable, Sendable {
    let ok: Bool
    let bridgeSchemaVersion: Int
    let macAppVersion: String
    let ackedAt: Date
    let nativeSnapshots: [BridgeSnapshot]
    let settings: BridgeSettings?
    let commands: [BridgeCommand]
    let error: String?
}

// MARK: - Snapshot

/// Provider usage snapshot exchanged on the wire. Both sides produce and consume this shape.
struct BridgeSnapshot: Codable, Sendable {
    /// Raw `ProviderId.rawValue` string — both sides derive display strings locally.
    let provider: String
    let capturedAt: Date
    let estimated: Bool?
    let shortWindow: BridgeWindow
    let longWindow: BridgeWindow?
    let planLabel: String
}

/// A single usage window as exchanged on the wire.
struct BridgeWindow: Codable, Sendable {
    let label: String
    /// Utilization expressed as a fraction in 0...1.
    let utilization: Double
    let resetsAt: Date
    let windowDurationSec: TimeInterval
    let sublabelOverride: String?
}

// MARK: - Settings sync

/// Provider visibility settings, keyed by `ProviderId.rawValue`.
/// Timestamp-wins conflict resolution applies per provider key.
struct BridgeSettings: Codable, Sendable {
    let providerVisibility: [String: ProviderVisibilitySetting]
    /// Tab order, newest `lastChangedAt` wins. Optional so an older Mac app or
    /// extension that doesn't know about it simply ignores the field.
    var providerOrder: ProviderOrderSetting? = nil
}

/// The user's provider tab order (`ProviderId.rawValue`s), stamped for
/// newest-wins reconciliation. One timestamp for the whole list, because a
/// reorder is a single gesture that moves several providers at once.
struct ProviderOrderSetting: Codable, Sendable, Equatable {
    var order: [String]
    var lastChangedAt: Date
}

// MARK: - Actions / commands

/// Actions the extension is requesting the Mac app perform.
struct BridgeRequestedActions: Codable, Sendable {
    let refreshNativeProviders: Bool?
}

/// A command the Mac app sends to the extension.
/// Unknown `kind` values are silently ignored by the receiver.
struct BridgeCommand: Codable, Sendable {
    let kind: String
}

// MARK: - JSON coding helpers

extension JSONEncoder {
    /// Shared encoder configured for bridge wire encoding (ISO 8601 dates).
    static var bridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    /// Shared decoder configured for bridge wire decoding (ISO 8601 dates).
    static var bridge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
