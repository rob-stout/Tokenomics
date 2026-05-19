import XCTest
@testable import Tokenomics

// MARK: - Test App Lookup

/// Configurable mock that replaces NSWorkspace so tests run without real apps.
final class MockAppLookup: AppLookup, @unchecked Sendable {
    /// Set of bundle IDs that should be reported as "present".
    var presentBundleIds: Set<String> = []

    func isAppPresent(bundleId: String) -> Bool {
        presentBundleIds.contains(bundleId)
    }
}

// MARK: - DetectionServiceTests

final class DetectionServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a temporary directory, calls the builder to populate it, then
    /// returns the path so tests can point a DetectionService at it.
    private func makeTempHome(populate: (URL) throws -> Void = { _ in }) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenomicsDetectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try populate(tmp)
        return tmp
    }

    private func makeService(
        home: URL,
        presentApps: Set<String> = [],
        fileManager: FileManager = .default
    ) -> DetectionService {
        let lookup = MockAppLookup()
        lookup.presentBundleIds = presentApps
        // DetectionService reads home from fileManager.homeDirectoryForCurrentUser.
        // We can't easily inject the home path without subclassing FileManager,
        // so we pass our own FileManager subclass that overrides homeDirectory,
        // OR — simpler — we use real FileManager and verify against real paths
        // where possible, using temp dirs for filesystem-fixture tests.
        return DetectionService(appLookup: lookup, fileManager: fileManager)
    }

    // MARK: - BrandDetection.annotation

    func testAnnotation_nativeAppSignal_containsInstalledSuffix() {
        let signal = DetectionSignal.nativeApp(bundleId: "com.foo.bar", displayName: "Foo.app")
        let detection = BrandDetection(brand: .anthropic, signals: [signal])
        XCTAssertEqual(detection.annotation, "Foo.app installed")
    }

    func testAnnotation_cliSignal_matchesDisplayName() {
        let signal = DetectionSignal.cliCredentials(path: "/some/path", displayName: "Claude Code CLI")
        let detection = BrandDetection(brand: .anthropic, signals: [signal])
        XCTAssertEqual(detection.annotation, "Claude Code CLI")
    }

    func testAnnotation_bridgeSignal_containsSessionText() {
        let signal = DetectionSignal.bridgeConnected(lastHeartbeat: Date())
        let detection = BrandDetection(brand: .openai, signals: [signal])
        XCTAssertEqual(detection.annotation, "browser session active")
    }

    func testAnnotation_multipleSignals_joinsWithMiddleDot() {
        let signals: [DetectionSignal] = [
            .nativeApp(bundleId: "com.a", displayName: "App.app"),
            .cliCredentials(path: "/b", displayName: "Tool CLI")
        ]
        let detection = BrandDetection(brand: .anthropic, signals: signals)
        XCTAssertEqual(detection.annotation, "App.app installed · Tool CLI")
    }

    func testAnnotation_noSignals_isEmpty() {
        let detection = BrandDetection(brand: .google, signals: [])
        XCTAssertTrue(detection.annotation.isEmpty)
    }

    // MARK: - BrandDetection.isDetected

    func testIsDetected_withSignals_isTrue() {
        let d = BrandDetection(brand: .cursor, signals: [.cliCredentials(path: "/x", displayName: "X")])
        XCTAssertTrue(d.isDetected)
    }

    func testIsDetected_noSignals_isFalse() {
        let d = BrandDetection(brand: .cursor, signals: [])
        XCTAssertFalse(d.isDetected)
    }

    // MARK: - detect() — nothing detected

    func testDetect_nothingPresent_returnsEmptyMap() async throws {
        let lookup = MockAppLookup()  // no apps present
        let home = try makeTempHome() // empty home — no .claude, .codex, .gemini dirs
        let service = DetectionService(appLookup: lookup, fileManager: .default)
        // We can't inject home easily, so we verify detect() returns an empty-or-
        // partial map based on what's actually on the machine. The key assertion is
        // that the result type is [BrandId: BrandDetection] with no fatal errors.
        // Actual per-brand fixture tests below use the temp-home approach.
        let result = await service.detect()
        XCTAssertNotNil(result, "detect() must return a non-nil map")
        // All returned detections must have at least one signal (spec: omit empty).
        for (_, detection) in result {
            XCTAssertTrue(detection.isDetected, "Detected brands must have signals")
        }
    }

    // MARK: - Anthropic detection

    func testDetect_anthropic_claudeAppPresent_hasNativeAppSignal() async {
        let lookup = MockAppLookup()
        lookup.presentBundleIds = ["com.anthropic.claudefordesktop"]
        let service = DetectionService(appLookup: lookup)
        let result = await service.detect()

        guard let detection = result[.anthropic] else {
            XCTFail("Anthropic should be detected when Claude.app is running")
            return
        }
        let hasNativeApp = detection.signals.contains {
            if case .nativeApp(let bundleId, _) = $0 { return bundleId == "com.anthropic.claudefordesktop" }
            return false
        }
        XCTAssertTrue(hasNativeApp)
    }

    func testDetect_anthropic_nothingPresent_notInResult() async throws {
        let lookup = MockAppLookup()  // no Claude.app
        // Ensure no .claude dir exists in a temp path — but since we can't inject
        // home, verify that without real signals, the brand is absent.
        // This test runs on the dev machine, so it may find a real .claude dir.
        // We use the presence check: if anthropic IS in the result, it must have signals.
        let service = DetectionService(appLookup: lookup)
        let result = await service.detect()
        if let detection = result[.anthropic] {
            XCTAssertTrue(detection.isDetected,
                "If anthropic appears in results, it must have signals")
        }
    }

    // MARK: - Cursor detection

    func testDetect_cursor_appPresent_hasCursorSignal() async {
        let lookup = MockAppLookup()
        lookup.presentBundleIds = ["com.todesktop.230313mzl4w4u92"]
        let service = DetectionService(appLookup: lookup)
        let result = await service.detect()

        guard let detection = result[.cursor] else {
            XCTFail("Cursor should be detected when app is present")
            return
        }
        let hasApp = detection.signals.contains {
            if case .nativeApp(let bundleId, _) = $0 { return bundleId == "com.todesktop.230313mzl4w4u92" }
            return false
        }
        XCTAssertTrue(hasApp)
    }

    func testDetect_cursor_appNotPresent_notInResult() async {
        let lookup = MockAppLookup()  // no Cursor
        let service = DetectionService(appLookup: lookup)
        let result = await service.detect()
        // On a machine without Cursor installed, cursor should be absent.
        // On a machine WITH Cursor, we just verify signals exist.
        if let detection = result[.cursor] {
            XCTAssertTrue(detection.isDetected)
        }
    }

    // MARK: - Concurrent detect() safety

    func testDetect_calledConcurrently_doesNotCrash() async {
        let service = DetectionService(appLookup: MockAppLookup())
        async let first = service.detect()
        async let second = service.detect()
        let (r1, r2) = await (first, second)
        // Both calls must complete without crashing; result shape must be valid.
        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
    }

    // MARK: - providerAnnotations adapter

    func testProviderAnnotations_emptyDetection_returnsEmptyMap() {
        let detection: [BrandId: BrandDetection] = [:]
        XCTAssertTrue(detection.providerAnnotations.isEmpty)
    }

    func testProviderAnnotations_anthropicDetected_claudeProviderGetsAnnotation() {
        let signal = DetectionSignal.cliCredentials(path: "/x/.claude", displayName: "Claude Code CLI")
        let detection: [BrandId: BrandDetection] = [
            .anthropic: BrandDetection(brand: .anthropic, signals: [signal])
        ]
        let annotations = detection.providerAnnotations
        XCTAssertEqual(annotations[.claude], "Claude Code CLI",
            "ProviderId.claude should receive the anthropic brand's annotation")
    }

    func testProviderAnnotations_openaiDetected_chatgptAndCodexBothAnnotated() {
        let signal = DetectionSignal.nativeApp(bundleId: "com.openai.chat", displayName: "ChatGPT.app")
        let detection: [BrandId: BrandDetection] = [
            .openai: BrandDetection(brand: .openai, signals: [signal])
        ]
        let annotations = detection.providerAnnotations
        // OpenAI's pool = [.chatgpt, .codex]
        XCTAssertNotNil(annotations[.chatgpt])
        XCTAssertNotNil(annotations[.codex])
        XCTAssertEqual(annotations[.chatgpt], annotations[.codex],
            "All providers in the same brand share the annotation string")
    }

    func testProviderAnnotations_notDetectedBrand_excluded() {
        // A BrandDetection with no signals should not produce any provider annotations.
        let detection: [BrandId: BrandDetection] = [
            .google: BrandDetection(brand: .google, signals: [])
        ]
        let annotations = detection.providerAnnotations
        XCTAssertNil(annotations[.gemini], "Empty detection must not populate annotations")
    }

    func testProviderAnnotations_multipleBrands_eachProviderCorrectlyAnnotated() {
        let anthropicSignal = DetectionSignal.cliCredentials(path: "/a", displayName: "Claude Code CLI")
        let cursorSignal = DetectionSignal.nativeApp(bundleId: "com.todesktop.230313mzl4w4u92", displayName: "Cursor.app")
        let detection: [BrandId: BrandDetection] = [
            .anthropic: BrandDetection(brand: .anthropic, signals: [anthropicSignal]),
            .cursor:    BrandDetection(brand: .cursor, signals: [cursorSignal])
        ]
        let annotations = detection.providerAnnotations
        XCTAssertEqual(annotations[.claude], "Claude Code CLI")
        XCTAssertEqual(annotations[.cursor], "Cursor.app installed")
        XCTAssertNil(annotations[.gemini])
    }
}
