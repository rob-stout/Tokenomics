import Foundation
import SafariServices
import os

// MARK: - SafariWebExtensionHandler

/// In-process bridge for the Tokenomics Safari Web Extension.
///
/// Mirrors `TokenomicsBridge/main.swift`'s stdio Native Messaging Host: same
/// wire schema (`Tokenomics/Models/BridgeWireTypes.swift`), same
/// merge/compose/locking logic (`TokenomicsBridge/BridgeCore.swift`), same
/// App-Group files (`ext-side.json` / `mac-side.json` / `bridge.lock`).
/// Safari routes `browser.runtime.sendNativeMessage` straight to this
/// in-process extension handler instead of spawning a stdio host, so there's
/// no NMH framing step and no separate process — everything downstream of
/// "decode the request" calls the exact same `BridgeCore` functions the CLI
/// tool does.
///
/// The ONLY divergence from the stdio tool is container resolution: this
/// handler runs sandboxed, so it resolves the App Group container via
/// `BridgeFileIO.sandboxedContainerURL()` (the entitlement-gated API) instead
/// of the stdio tool's manual path — see that method's doc comment.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private static let log = Logger(subsystem: "com.robstout.tokenomics.safari.extension", category: "bridge")
    private static let supportedSchemaVersion = 1

    func beginRequest(with context: NSExtensionContext) {
        guard let requestData = Self.extractMessageData(from: context) else {
            Self.log.error("no message payload in extension request")
            Self.complete(context: context, response: Self.errorResponse("no message payload"))
            return
        }

        let request: BridgeRequest
        do {
            request = try JSONDecoder.bridge.decode(BridgeRequest.self, from: requestData)
        } catch {
            Self.log.error("decode failed: \(error)")
            Self.complete(context: context, response: Self.errorResponse("decode failed: \(error)"))
            return
        }

        guard request.schemaVersion <= Self.supportedSchemaVersion else {
            Self.complete(context: context, response: Self.errorResponse("unsupported schemaVersion \(request.schemaVersion)"))
            return
        }

        guard let container = BridgeFileIO.sandboxedContainerURL() else {
            Self.log.error("no app group: containerURL(forSecurityApplicationGroupIdentifier:) returned nil")
            Self.complete(context: context, response: Self.errorResponse("no app group container"))
            return
        }

        Self.complete(context: context, response: Self.handle(request: request, container: container))
    }

    // MARK: - Core handling (mirrors TokenomicsBridge/main.swift steps 6-9)

    private static func handle(request: BridgeRequest, container: URL) -> BridgeResponse {
        let lockFd: Int32
        do {
            lockFd = try BridgeFileIO.acquireLock(in: container)
        } catch {
            log.error("flock failed: \(error)")
            return errorResponse("flock failed: \(error)")
        }
        defer { BridgeFileIO.releaseLock(lockFd) }

        let existingExtSide = BridgeFileIO.readExtSideState(from: container)
        let mergedExtSide = BridgeMerger.merge(existing: existingExtSide, request: request)

        do {
            try BridgeFileIO.writeExtSideState(mergedExtSide, to: container)
        } catch {
            // Non-fatal for the response path — same as the stdio tool.
            log.warning("failed to write ext-side.json: \(error)")
        }

        let macSide = BridgeFileIO.readMacSideState(from: container)
        return BridgeResponseComposer.compose(
            macSide: macSide,
            request: request,
            macAppVersion: macAppVersion()
        )
    }

    // MARK: - Message extraction

    /// Safari hands the JS message to us via
    /// `NSExtensionItem.userInfo[SFExtensionMessageKey]`. It may arrive as a
    /// dictionary (typical) or a JSON string depending on OS version — handle
    /// both defensively and re-serialize to `Data` either way so the rest of
    /// this handler only ever deals with `JSONDecoder.bridge`.
    private static func extractMessageData(from context: NSExtensionContext) -> Data? {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo,
              let raw = userInfo[SFExtensionMessageKey] else {
            return nil
        }

        if let string = raw as? String {
            return Data(string.utf8)
        }
        if JSONSerialization.isValidJSONObject(raw) {
            return try? JSONSerialization.data(withJSONObject: raw)
        }
        return nil
    }

    // MARK: - Response delivery

    private static func complete(context: NSExtensionContext, response: BridgeResponse) {
        let responseItem = NSExtensionItem()
        if let jsonData = try? JSONEncoder.bridge.encode(response),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
            responseItem.userInfo = [SFExtensionMessageKey: jsonObject]
        }
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }

    // MARK: - Helpers (mirror TokenomicsBridge/main.swift)

    private static func macAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static func errorResponse(_ message: String) -> BridgeResponse {
        BridgeResponse(
            ok: false,
            bridgeSchemaVersion: 1,
            macAppVersion: macAppVersion(),
            ackedAt: Date(),
            nativeSnapshots: [],
            settings: nil,
            commands: [],
            error: message
        )
    }
}
