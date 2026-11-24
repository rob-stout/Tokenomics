import Foundation
import Darwin

// MARK: - Diagnostic logging

/// Writes one line to ~/Library/Logs/Tokenomics/bridge.log.
/// Rotates the log file when it exceeds 1 MB (truncates and writes a marker).
private func bridgeLog(_ message: String) {
    let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Tokenomics")
    let logURL = logDir.appendingPathComponent("bridge.log")

    try? FileManager.default.createDirectory(
        at: logDir,
        withIntermediateDirectories: true
    )

    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    let lineData = Data(line.utf8)

    if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
       let size = attrs[.size] as? Int,
       size > 1_048_576 {
        // Rotate: truncate and write a marker.
        let marker = Data("--- rotated ---\n".utf8)
        try? marker.write(to: logURL)
    }

    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(lineData)
        try? handle.close()
    } else {
        // File doesn't exist yet — create it.
        try? lineData.write(to: logURL)
    }
}

// MARK: - NMH framing helpers (I/O layer)

/// Reads exactly `count` bytes from stdin. Returns nil on EOF.
private func readBytes(_ count: Int) -> Data? {
    guard count > 0 else { return Data() }
    let data = FileHandle.standardInput.readData(ofLength: count)
    return data.count == count ? data : nil
}

/// Writes a framed NMH response to stdout.
private func writeResponse(_ response: BridgeResponse) {
    guard let jsonData = try? JSONEncoder.bridge.encode(response) else { return }
    let frame = BridgeFraming.encode(jsonData: jsonData)
    FileHandle.standardOutput.write(frame)
}

/// Writes an error-only response frame and exits with the given code.
private func exitWithError(_ message: String, code: Int32) -> Never {
    bridgeLog("ERROR: \(message)")
    let response = BridgeResponse(
        ok: false,
        bridgeSchemaVersion: 1,
        macAppVersion: macAppVersion(),
        ackedAt: Date(),
        nativeSnapshots: [],
        settings: nil,
        commands: [],
        error: message
    )
    writeResponse(response)
    exit(code)
}

// MARK: - Version helper

private func macAppVersion() -> String {
    // Bundle.main is the tool itself, so walk up from
    // <App>.app/Contents/Helpers/TokenomicsBridge to the enclosing app bundle.
    let exe = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    let appURL = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard appURL.pathExtension == "app",
          let version = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    else { return "unknown" }
    return version
}

// MARK: - Entry point

// Suppress stderr — Chrome captures NMH stderr into its own log stream.
// All diagnostics go to bridge.log instead.
freopen("/dev/null", "w", stderr)

bridgeLog("bridge started")

// Step 1 — Read the 4-byte length header.
guard let headerBytes = readBytes(4) else {
    // EOF before any bytes — Chrome closed the pipe; exit silently.
    bridgeLog("EOF on stdin before header — exiting cleanly")
    exit(0)
}

// Step 2 — Validate declared length.
let declaredLength: Int
do {
    declaredLength = try BridgeFraming.parseLength(from: headerBytes)
} catch BridgeFraming.FramingError.messageTooLarge(let declared, let cap) {
    exitWithError("message too large: declared \(declared) bytes, cap is \(cap)", code: 1)
} catch {
    exitWithError("framing error: \(error)", code: 1)
}

// Step 3 — Read the JSON body.
guard let bodyBytes = readBytes(declaredLength) else {
    exitWithError("unexpected EOF reading message body (expected \(declaredLength) bytes)", code: 1)
}

// Step 4 — Decode the request.
let request: BridgeRequest
do {
    request = try JSONDecoder.bridge.decode(BridgeRequest.self, from: bodyBytes)
} catch {
    exitWithError("decode failed: \(error)", code: 1)
}

bridgeLog("request from extensionId=\(request.extensionId) schemaVersion=\(request.schemaVersion) snapshots=\(request.snapshots.count)")

// Step 5 — Validate schema version.
let supportedSchemaVersion = 1
guard request.schemaVersion <= supportedSchemaVersion else {
    exitWithError("unsupported schemaVersion \(request.schemaVersion)", code: 1)
}

// Step 6 — Resolve the shared bridge directory.
guard let container = BridgeFileIO.containerURL() else {
    exitWithError("no bridge directory", code: 1)
}

// Step 7 — Acquire exclusive flock on bridge.lock.
let lockFd: Int32
do {
    lockFd = try BridgeFileIO.acquireLock(in: container)
} catch {
    exitWithError("flock failed: \(error)", code: 1)
}

defer {
    // Step 10 — Release flock on any exit path.
    BridgeFileIO.releaseLock(lockFd)
    bridgeLog("flock released")
}

// Step 8 — Read ext-side.json, merge, write back atomically.
let existingExtSide = BridgeFileIO.readExtSideState(from: container)
let mergedExtSide = BridgeMerger.merge(existing: existingExtSide, request: request)

do {
    try BridgeFileIO.writeExtSideState(mergedExtSide, to: container)
    bridgeLog("ext-side.json written (snapshots=\(mergedExtSide.snapshots.count))")
} catch {
    // Non-fatal for the response path — log and continue.
    bridgeLog("WARNING: failed to write ext-side.json: \(error)")
}

// Step 9 — Read mac-side.json to compose the response.
let macSide = BridgeFileIO.readMacSideState(from: container)
let response = BridgeResponseComposer.compose(
    macSide: macSide,
    request: request,
    macAppVersion: macAppVersion()
)

bridgeLog("response composed nativeSnapshots=\(response.nativeSnapshots.count) commands=\(response.commands.count)")

// Step 11 — Write framed response to stdout.
writeResponse(response)

bridgeLog("bridge exiting ok")
exit(0)
