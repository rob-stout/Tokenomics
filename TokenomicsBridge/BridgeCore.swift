import Foundation
import Darwin

// MARK: - State-file shapes

/// State written by the bridge on behalf of the browser extension.
/// The Mac app's WebCompanionService reads this file.
struct ExtSideState: Codable, Sendable {
    var updatedAt: Date
    /// Per-provider snapshots keyed by ProviderId.rawValue.
    var snapshots: [String: BridgeSnapshot]
    /// Per-provider visibility settings keyed by ProviderId.rawValue.
    var providerVisibility: [String: ProviderVisibilitySetting]
}

/// State written by the Mac app and read by the bridge to compose responses.
/// The bridge never writes this file — Agent 3 (MacSideStateExporter) owns it.
struct MacSideState: Codable, Sendable {
    var updatedAt: Date
    var macAppVersion: String
    /// Per-provider snapshots from native sources, keyed by ProviderId.rawValue.
    var nativeSnapshots: [String: BridgeSnapshot]
    /// Per-provider visibility settings keyed by ProviderId.rawValue.
    var providerVisibility: [String: ProviderVisibilitySetting]
    /// Commands to deliver in the next bridge response.
    /// The bridge reads but does not mutate this array.
    var pendingCommands: [BridgeCommand]
}

// MARK: - BridgeFraming

/// Pure functions for Chrome Native Messaging Host wire framing.
///
/// Chrome NMH protocol: each message is a 4-byte native-endian UInt32 length
/// followed by that many bytes of UTF-8 JSON.
enum BridgeFraming {

    enum FramingError: Error {
        /// stdin returned fewer bytes than expected.
        case unexpectedEOF
        /// The declared message length exceeds the safety cap.
        case messageTooLarge(declared: Int, cap: Int)
    }

    static let maxMessageBytes = 65_536

    /// Encodes a JSON payload into a length-prefixed NMH frame.
    ///
    /// - Parameter jsonData: Raw UTF-8 JSON bytes.
    /// - Returns: 4-byte little-endian length prefix + JSON bytes.
    static func encode(jsonData: Data) -> Data {
        var length = UInt32(jsonData.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(jsonData)
        return frame
    }

    /// Parses the length prefix from the first 4 bytes of a buffer.
    ///
    /// - Parameter headerBytes: Exactly 4 bytes from stdin.
    /// - Returns: The declared message length as an Int.
    /// - Throws: `FramingError.messageTooLarge` if the declared length exceeds the cap.
    static func parseLength(from headerBytes: Data) throws -> Int {
        precondition(headerBytes.count == 4, "parseLength requires exactly 4 bytes")
        let raw = headerBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
        let length = Int(UInt32(littleEndian: raw))
        if length > maxMessageBytes {
            throw FramingError.messageTooLarge(declared: length, cap: maxMessageBytes)
        }
        return length
    }

    /// Reads one NMH-framed message from a raw Data buffer (no I/O).
    ///
    /// The buffer must contain at least 4 bytes (the length header) plus the
    /// declared payload length.
    ///
    /// - Parameter buffer: The full stdin contents (at least 4 bytes).
    /// - Returns: The JSON payload bytes.
    /// - Throws: `FramingError` on EOF or oversized message.
    static func decode(from buffer: Data) throws -> Data {
        guard buffer.count >= 4 else {
            throw FramingError.unexpectedEOF
        }
        let header = buffer.prefix(4)
        let length = try parseLength(from: header)
        guard buffer.count >= 4 + length else {
            throw FramingError.unexpectedEOF
        }
        return buffer.subdata(in: 4 ..< (4 + length))
    }
}

// MARK: - BridgeMerger

/// Merges browser-extension state (from a BridgeRequest) into existing ExtSideState.
///
/// Conflict resolution: per-key, the entry with the more recent timestamp wins.
/// Snapshots use `capturedAt`; visibility settings use `lastChangedAt`.
enum BridgeMerger {

    /// Produces a merged ExtSideState from an existing state and an incoming request.
    ///
    /// - Parameters:
    ///   - existing: The current contents of ext-side.json, or nil if the file is absent.
    ///   - request: The decoded BridgeRequest from the extension.
    ///   - now: The wall-clock time used to stamp `updatedAt`.
    /// - Returns: The merged ExtSideState ready to be written back to ext-side.json.
    static func merge(
        existing: ExtSideState?,
        request: BridgeRequest,
        now: Date = Date()
    ) -> ExtSideState {
        var snapshots = existing?.snapshots ?? [:]
        var providerVisibility = existing?.providerVisibility ?? [:]

        // Merge snapshots: later capturedAt wins per provider key.
        for incoming in request.snapshots {
            let key = incoming.provider
            if let current = snapshots[key] {
                if incoming.capturedAt > current.capturedAt {
                    snapshots[key] = incoming
                }
            } else {
                snapshots[key] = incoming
            }
        }

        // Merge visibility settings: later lastChangedAt wins per provider key.
        if let incomingSettings = request.settings {
            for (key, incoming) in incomingSettings.providerVisibility {
                if let current = providerVisibility[key] {
                    if incoming.lastChangedAt > current.lastChangedAt {
                        providerVisibility[key] = incoming
                    }
                } else {
                    providerVisibility[key] = incoming
                }
            }
        }

        return ExtSideState(
            updatedAt: now,
            snapshots: snapshots,
            providerVisibility: providerVisibility
        )
    }
}

// MARK: - BridgeResponseComposer

/// Composes a BridgeResponse from the current MacSideState and the incoming request.
enum BridgeResponseComposer {

    /// Builds a successful BridgeResponse using data from mac-side.json.
    ///
    /// - Parameters:
    ///   - macSide: The current contents of mac-side.json, or nil if the file is absent.
    ///   - request: The decoded BridgeRequest (used to stamp ackedAt from envelopeSentAt).
    ///   - macAppVersion: The running Mac app version string.
    ///   - now: Wall-clock time used to stamp `ackedAt`.
    /// - Returns: A fully formed BridgeResponse.
    static func compose(
        macSide: MacSideState?,
        request: BridgeRequest,
        macAppVersion: String,
        now: Date = Date()
    ) -> BridgeResponse {
        let nativeSnapshots = macSide.map { Array($0.nativeSnapshots.values) } ?? []
        let commands = macSide?.pendingCommands ?? []
        let mergedVisibility = mergeVisibility(
            macSide: macSide?.providerVisibility ?? [:],
            requestSettings: request.settings
        )
        let settings = mergedVisibility.isEmpty ? nil : BridgeSettings(providerVisibility: mergedVisibility)

        return BridgeResponse(
            ok: true,
            bridgeSchemaVersion: 1,
            macAppVersion: macAppVersion,
            ackedAt: now,
            nativeSnapshots: nativeSnapshots,
            settings: settings,
            commands: commands,
            error: nil
        )
    }

    /// Merges Mac-side visibility with the extension's incoming visibility settings,
    /// using the same timestamp-wins rule.
    private static func mergeVisibility(
        macSide: [String: ProviderVisibilitySetting],
        requestSettings: BridgeSettings?
    ) -> [String: ProviderVisibilitySetting] {
        var merged = macSide
        guard let incoming = requestSettings?.providerVisibility else { return merged }
        for (key, setting) in incoming {
            if let existing = merged[key] {
                if setting.lastChangedAt > existing.lastChangedAt {
                    merged[key] = setting
                }
            } else {
                merged[key] = setting
            }
        }
        return merged
    }
}

// MARK: - BridgeFileIO

/// flock-protected atomic read/write helpers for the App Group container.
///
/// All methods are synchronous and intended to run on the bridge's main thread.
/// The bridge is a short-lived CLI process — no concurrency needed.
enum BridgeFileIO {

    enum IOError: Error {
        case containerUnavailable
        case flockFailed(Int32)
        case readFailed(Error)
        case writeFailed(Error)
        case renameFailed(Int32)
    }

    private static let groupIdentifier = "group.com.robstout.tokenomics"
    private static let extSideFilename = "ext-side.json"
    private static let macSideFilename = "mac-side.json"
    private static let lockFilename = "bridge.lock"

    /// Resolves the App Group container URL.
    ///
    /// This is a non-sandboxed Developer ID command-line tool, so it deliberately
    /// does NOT carry the `com.apple.security.application-groups` entitlement —
    /// tool targets can't bear a provisioning profile, and an unauthorized App
    /// Group entitlement makes the embedding app fail Developer ID export
    /// ("no valid distribution method"). The group container lives at a fixed
    /// path that any non-sandboxed process can reach directly, so resolve it
    /// manually rather than via the entitlement-gated
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` API (which returns
    /// nil without the entitlement). The sandboxed widget and the main app reach
    /// the identical path through the API, so all three share one directory.
    static func containerURL() -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(groupIdentifier, isDirectory: true)
        // Ensure it exists — the bridge may run before an entitled process has
        // created the container. Same path the API would hand back.
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Opens (or creates) the lock file and acquires an exclusive flock.
    ///
    /// - Returns: The open file descriptor. Caller must `close(fd)` and `flock(fd, LOCK_UN)`.
    /// - Throws: `IOError.containerUnavailable` or `IOError.flockFailed`.
    static func acquireLock(in container: URL) throws -> Int32 {
        let lockPath = container.appendingPathComponent(lockFilename).path
        let fd = open(lockPath, O_RDWR | O_CREAT, 0o666)
        guard fd >= 0 else {
            throw IOError.flockFailed(errno)
        }
        guard flock(fd, LOCK_EX) == 0 else {
            close(fd)
            throw IOError.flockFailed(errno)
        }
        return fd
    }

    /// Releases the flock and closes the file descriptor.
    static func releaseLock(_ fd: Int32) {
        flock(fd, LOCK_UN)
        close(fd)
    }

    /// Reads and decodes `ext-side.json` from the container.
    ///
    /// Returns nil if the file is absent (treated as empty state by the caller).
    static func readExtSideState(from container: URL) -> ExtSideState? {
        let url = container.appendingPathComponent(extSideFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.bridge.decode(ExtSideState.self, from: data)
    }

    /// Atomically writes `state` to `ext-side.json` using a tmp-file + rename.
    static func writeExtSideState(_ state: ExtSideState, to container: URL) throws {
        let encoder = JSONEncoder.bridge
        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw IOError.writeFailed(error)
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let tmpName = "\(extSideFilename).tmp.\(pid)"
        let tmpURL = container.appendingPathComponent(tmpName)
        let destURL = container.appendingPathComponent(extSideFilename)

        do {
            try data.write(to: tmpURL, options: .atomic)
        } catch {
            throw IOError.writeFailed(error)
        }

        let result = rename(tmpURL.path, destURL.path)
        guard result == 0 else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw IOError.renameFailed(errno)
        }
    }

    /// Reads and decodes `mac-side.json` from the container.
    ///
    /// Returns nil if the file is absent (bridge composes an empty response).
    static func readMacSideState(from container: URL) -> MacSideState? {
        let url = container.appendingPathComponent(macSideFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.bridge.decode(MacSideState.self, from: data)
    }
}
