import XCTest
@testable import Tokenomics

// Scripted reader stands in for the keychain: these tests must never touch the real one.

private final class ScriptedReader: @unchecked Sendable {
    private let lock = NSLock()
    private var silentQueue: [ClaudeCredentialRead]
    private var interactiveQueue: [ClaudeCredentialRead]
    private(set) var silentCalls = 0
    private(set) var interactiveCalls = 0
    private(set) var exclusions: [Set<String>] = []

    private(set) var interactiveExclusions: [Set<String>] = []

    private func recordInteractiveExclusion(_ value: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        interactiveExclusions.append(value)
    }

    private func recordExclusion(_ value: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        exclusions.append(value)
    }

    /// Fake keychain-item modification date; tests mutate it to simulate Claude Code
    /// rewriting the item.
    private var mdat: Date?
    func setModificationDate(_ date: Date?) { lock.lock(); mdat = date; lock.unlock() }
    private func currentModificationDate() -> Date? { lock.lock(); defer { lock.unlock() }; return mdat }

    /// Tokens the fake credentials file "holds".
    private var fileTokens: Set<String> = []
    func setFileTokens(_ tokens: Set<String>) { lock.lock(); fileTokens = tokens; lock.unlock() }
    private func isFileToken(_ token: String) -> Bool { lock.lock(); defer { lock.unlock() }; return fileTokens.contains(token) }

    init(silent: [ClaudeCredentialRead] = [], interactive: [ClaudeCredentialRead] = [], modificationDate: Date? = nil) {
        silentQueue = silent
        interactiveQueue = interactive
        mdat = modificationDate
    }

    var reader: ClaudeCredentialStore.Reader {
        .init(
            silent: { [self] excluding in
                recordExclusion(excluding)
                return next(\.silentQueue, count: \.silentCalls)
            },
            interactive: { [self] excluding in
                recordInteractiveExclusion(excluding)
                return next(\.interactiveQueue, count: \.interactiveCalls)
            },
            modificationDate: { [self] in currentModificationDate() },
            isFileToken: { [self] in isFileToken($0) }
        )
    }

    private func next(
        _ queue: ReferenceWritableKeyPath<ScriptedReader, [ClaudeCredentialRead]>,
        count: ReferenceWritableKeyPath<ScriptedReader, Int>
    ) -> ClaudeCredentialRead {
        lock.lock(); defer { lock.unlock() }
        self[keyPath: count] += 1
        return self[keyPath: queue].isEmpty ? .notFound : self[keyPath: queue].removeFirst()
    }
}

/// Reader whose first silent call returns `.needsAuthorization` after a delay, later
/// silent calls return `.needsAuthorization` immediately, and interactive is slow
/// enough that concurrent callers overlap.
private final class SlowReader: @unchecked Sendable {
    private let lock = NSLock()
    private let interactiveResult: ClaudeCredentialRead
    private let firstSilentDelay: TimeInterval
    private var silentCount = 0
    private(set) var interactiveCalls = 0

    init(interactiveResult: ClaudeCredentialRead, firstSilentDelay: TimeInterval = 0) {
        self.interactiveResult = interactiveResult
        self.firstSilentDelay = firstSilentDelay
    }

    var reader: ClaudeCredentialStore.Reader {
        .init(
            silent: { [self] _ in
                let delay = bump { silentCount += 1; return silentCount == 1 ? firstSilentDelay : 0 }
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                return .needsAuthorization
            },
            interactive: { [self] _ in
                bump { interactiveCalls += 1 }
                try? await Task.sleep(nanoseconds: 100_000_000)
                return interactiveResult
            }
        )
    }

    private func bump<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

final class ClaudeCredentialStoreTests: XCTestCase {

    func testCurrentToken_cachesFoundToken_andReadsOnce() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-a")])
        let store = ClaudeCredentialStore(reader: script.reader)

        let first = await store.currentToken()
        let second = await store.currentToken()

        XCTAssertEqual(first, .found(accessToken: "sk-ant-a"))
        XCTAssertEqual(second, .found(accessToken: "sk-ant-a"))
        XCTAssertEqual(script.silentCalls, 1)
    }

    func testCurrentToken_doesNotCacheNeedsAuthorization() async {
        let script = ScriptedReader(silent: [.needsAuthorization, .found(accessToken: "sk-ant-a")])
        let store = ClaudeCredentialStore(reader: script.reader)

        let first = await store.currentToken()
        let second = await store.currentToken()

        XCTAssertEqual(first, .needsAuthorization)
        XCTAssertEqual(second, .found(accessToken: "sk-ant-a"))
        XCTAssertEqual(script.silentCalls, 2)
    }

    func testCurrentToken_doesNotCacheNotFound() async {
        let script = ScriptedReader(silent: [.notFound, .found(accessToken: "sk-ant-a")])
        let store = ClaudeCredentialStore(reader: script.reader)

        _ = await store.currentToken()
        let second = await store.currentToken()

        XCTAssertEqual(second, .found(accessToken: "sk-ant-a"))
    }

    func testAfterUnauthorized_newToken_isReturnedAndCached() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-old"), .found(accessToken: "sk-ant-new")])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-old")
        let cached = await store.currentToken()

        XCTAssertEqual(result, .found(accessToken: "sk-ant-new"))
        XCTAssertEqual(cached, .found(accessToken: "sk-ant-new"))
        XCTAssertEqual(script.silentCalls, 2)
    }

    func testAfterUnauthorized_sameToken_isStale() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-old"), .found(accessToken: "sk-ant-old")])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-old")

        XCTAssertEqual(result, .staleToken)
    }

    func testAfterUnauthorized_needsAuthorization_isSurfaced_andCacheDropped() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-old"), .needsAuthorization])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-old")

        XCTAssertEqual(result, .needsAuthorization)
    }

    func testAfterUnauthorized_notFound_isSurfaced() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-old"), .notFound])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-old")

        XCTAssertEqual(result, .notFound)
    }

    func testAfterUnauthorized_whenNewerTokenAlreadyCached_keepsIt() async {
        // A concurrent caller already refreshed the cache; a stale 401 must not wipe it.
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-new")])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-old")

        XCTAssertEqual(result, .found(accessToken: "sk-ant-new"))
        XCTAssertEqual(script.silentCalls, 1)
    }

    func testRequestAccess_needsAuthorization_goesInteractive_andCaches() async {
        let script = ScriptedReader(silent: [.needsAuthorization], interactive: [.found(accessToken: "sk-ant-a")])
        let store = ClaudeCredentialStore(reader: script.reader)

        let granted = await store.requestAccess()
        let cached = await store.currentToken()

        XCTAssertEqual(granted, .found(accessToken: "sk-ant-a"))
        XCTAssertEqual(cached, .found(accessToken: "sk-ant-a"))
        XCTAssertEqual(script.interactiveCalls, 1)
        XCTAssertEqual(script.silentCalls, 1)
    }

    func testRequestAccess_cachedToken_skipsAllReads() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-a")])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        let result = await store.requestAccess()

        XCTAssertEqual(result, .found(accessToken: "sk-ant-a"))
        XCTAssertEqual(script.silentCalls, 1)
        XCTAssertEqual(script.interactiveCalls, 0)
    }

    func testRequestAccess_silentSuccess_neverGoesInteractive() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-a")])
        let store = ClaudeCredentialStore(reader: script.reader)

        let result = await store.requestAccess()

        XCTAssertEqual(result, .found(accessToken: "sk-ant-a"))
        XCTAssertEqual(script.interactiveCalls, 0)
    }

    func testRequestAccess_denied_doesNotCache() async {
        let script = ScriptedReader(silent: [.needsAuthorization], interactive: [.needsAuthorization])
        let store = ClaudeCredentialStore(reader: script.reader)

        let result = await store.requestAccess()

        XCTAssertEqual(result, .needsAuthorization)
        let after = await store.currentToken()
        XCTAssertEqual(after, .notFound) // scripted silent queue is empty
        XCTAssertEqual(script.silentCalls, 2)
    }

    func testRequestAccess_concurrentCallers_shareOneInteractiveRead() async {
        let gate = SlowReader(interactiveResult: .found(accessToken: "sk-ant-a"))
        let store = ClaudeCredentialStore(reader: gate.reader)

        async let first = store.requestAccess()
        async let second = store.requestAccess()
        let results = await [first, second]

        XCTAssertEqual(results, [.found(accessToken: "sk-ant-a"), .found(accessToken: "sk-ant-a")])
        XCTAssertEqual(gate.interactiveCalls, 1)
    }

    func testCurrentToken_grantDuringSilentRead_winsOverStaleResult() async {
        // Silent read is suspended (returns needsAuthorization late) while a grant lands.
        let gate = SlowReader(interactiveResult: .found(accessToken: "sk-ant-fresh"), firstSilentDelay: 0.3)
        let store = ClaudeCredentialStore(reader: gate.reader)

        async let stale = store.currentToken()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let granted = await store.requestAccess()
        let late = await stale

        XCTAssertEqual(granted, .found(accessToken: "sk-ant-fresh"))
        XCTAssertEqual(late, .found(accessToken: "sk-ant-fresh"))
    }

    func testAfterUnauthorized_passesRejectedTokenAsExclusion() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-old"), .found(accessToken: "sk-ant-new")])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        _ = await store.tokenAfterUnauthorized(previous: "sk-ant-old")

        XCTAssertEqual(script.exclusions, [[], ["sk-ant-old"]])
    }

    func testRejectedToken_isNeverReturnedByCurrentToken() async {
        // Keychain keeps handing back the rejected token: must not be cached or returned.
        let script = ScriptedReader(silent: [
            .found(accessToken: "sk-ant-old"), .found(accessToken: "sk-ant-old"), .found(accessToken: "sk-ant-old")
        ])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()
        _ = await store.tokenAfterUnauthorized(previous: "sk-ant-old")

        let next = await store.currentToken()

        XCTAssertEqual(next, .staleToken)
    }

    func testRequestAccess_afterRejectedFileToken_reachesInteractive() async {
        // File holds stale T0 unless excluded; keychain needs authorization.
        let script = ScriptedReader(
            silent: [.found(accessToken: "sk-ant-T0"), .needsAuthorization, .needsAuthorization, .needsAuthorization],
            interactive: [.found(accessToken: "sk-ant-T1")]
        )
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()
        let afterReject = await store.tokenAfterUnauthorized(previous: "sk-ant-T0")
        let polled = await store.currentToken()

        let granted = await store.requestAccess()

        XCTAssertEqual(afterReject, .needsAuthorization)
        XCTAssertEqual(polled, .needsAuthorization)
        XCTAssertEqual(granted, .found(accessToken: "sk-ant-T1"))
        XCTAssertEqual(script.interactiveCalls, 1)
        XCTAssertEqual(script.interactiveExclusions, [["sk-ant-T0"]])
        XCTAssertEqual(script.exclusions, [[], ["sk-ant-T0"], ["sk-ant-T0"], ["sk-ant-T0"]])
    }

    // MARK: - Item version (modification date) semantics

    private let v1 = Date(timeIntervalSince1970: 1_000)
    private let v2 = Date(timeIntervalSince1970: 2_000)

    func testStale_mdatUnchanged_staysStale() async {
        // One-time Allow token dies; item untouched → Claude Code must run.
        let script = ScriptedReader(silent: [.needsAuthorization, .needsAuthorization, .needsAuthorization],
                                    interactive: [.found(accessToken: "sk-ant-once")], modificationDate: v1)
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.requestAccess()

        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-once")
        let polled = await store.currentToken()

        XCTAssertEqual(result, .staleToken)
        XCTAssertEqual(polled, .staleToken)
    }

    func testStale_thenItemRewritten_movesToNeedsAuthorization() async {
        let script = ScriptedReader(silent: [.needsAuthorization, .needsAuthorization, .needsAuthorization, .needsAuthorization],
                                    interactive: [.found(accessToken: "sk-ant-once")], modificationDate: v1)
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.requestAccess()
        _ = await store.tokenAfterUnauthorized(previous: "sk-ant-once")

        script.setModificationDate(v2) // user ran `claude` / /login
        let polled = await store.currentToken()
        let again = await store.currentToken()

        XCTAssertEqual(polled, .needsAuthorization)
        XCTAssertEqual(again, .needsAuthorization) // verdict cleared, not sticky
    }

    func testFileToken_rejected_keychainUnreadable_isNeedsAuthorizationNotStale() async {
        // Leftover file token T0 is not a keychain version; its 401 says nothing about the item.
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-T0"), .needsAuthorization],
                                    modificationDate: v1)
        script.setFileTokens(["sk-ant-T0"])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-T0")

        XCTAssertEqual(result, .needsAuthorization)
    }

    func testItemRewrittenWithSameDeadToken_requestAccessIsStale_andStaysStaleAtNewVersion() async {
        // Scenario D: item rewritten at a new mdat but still holds the rejected token.
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-dead"), .needsAuthorization, .needsAuthorization, .needsAuthorization],
                                    interactive: [.found(accessToken: "sk-ant-dead")], modificationDate: v1)
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()
        _ = await store.tokenAfterUnauthorized(previous: "sk-ant-dead")

        script.setModificationDate(v2)
        let granted = await store.requestAccess()
        let polled = await store.currentToken()

        XCTAssertEqual(granted, .staleToken)
        XCTAssertEqual(polled, .staleToken)
    }

    func testOneTimeAllowToken_rotatedByClaudeCode_isNeedsAuthorizationNotStale() async {
        let script = ScriptedReader(silent: [.needsAuthorization, .needsAuthorization],
                                    interactive: [.found(accessToken: "sk-ant-once")], modificationDate: v1)
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.requestAccess()

        script.setModificationDate(v2) // Claude Code rotated the token
        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-once")

        XCTAssertEqual(result, .needsAuthorization)
    }

    func testStale_unknownMdat_isNeverStale() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-a"), .needsAuthorization])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-a")

        XCTAssertEqual(result, .needsAuthorization)
    }

    func testAllRejectedTokens_areExcluded() async {
        let script = ScriptedReader(silent: [
            .found(accessToken: "sk-ant-1"), .found(accessToken: "sk-ant-2"), .found(accessToken: "sk-ant-3")
        ])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()
        _ = await store.tokenAfterUnauthorized(previous: "sk-ant-1")
        _ = await store.tokenAfterUnauthorized(previous: "sk-ant-2")

        XCTAssertEqual(script.exclusions, [[], ["sk-ant-1"], ["sk-ant-1", "sk-ant-2"]])
    }

    func testInteractiveToken_rejected_thenAllowReturnsSameToken_isStale() async {
        let script = ScriptedReader(
            silent: [.needsAuthorization, .needsAuthorization, .needsAuthorization],
            interactive: [.found(accessToken: "sk-ant-once"), .found(accessToken: "sk-ant-once")]
        )
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.requestAccess()
        _ = await store.tokenAfterUnauthorized(previous: "sk-ant-once")

        let again = await store.requestAccess()

        XCTAssertEqual(again, .staleToken)
    }

    func testSilentToken_rejected_withNeedsAuthorizationReread_staysNeedsAuthorization() async {
        let script = ScriptedReader(silent: [.found(accessToken: "sk-ant-a"), .needsAuthorization])
        let store = ClaudeCredentialStore(reader: script.reader)
        _ = await store.currentToken()

        let result = await store.tokenAfterUnauthorized(previous: "sk-ant-a")

        XCTAssertEqual(result, .needsAuthorization)
    }
}

// MARK: - KeychainService pure helpers (no keychain access)

final class KeychainServiceMappingTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testMap_statusCodes() {
        let json = data(#"{"claudeAiOauth":{"accessToken":"sk-ant-x","refreshToken":"r"}}"#)
        XCTAssertEqual(KeychainService.map(status: errSecSuccess, data: json), .found(accessToken: "sk-ant-x"))
        XCTAssertEqual(KeychainService.map(status: errSecItemNotFound, data: nil), .notFound)
        XCTAssertEqual(KeychainService.map(status: errSecAuthFailed, data: nil), .needsAuthorization)
        XCTAssertEqual(KeychainService.map(status: errSecInteractionNotAllowed, data: nil), .needsAuthorization)
        XCTAssertEqual(KeychainService.map(status: errSecUserCanceled, data: nil), .needsAuthorization)
        // Unknown codes: a tap shows at most one dialog, whereas .notFound would push
        // the user into a pointless re-login.
        XCTAssertEqual(KeychainService.map(status: -34018, data: nil), .needsAuthorization)
    }

    func testMap_successWithUnusableData_isNotFound() {
        XCTAssertEqual(KeychainService.map(status: errSecSuccess, data: data("garbage")), .notFound)
        XCTAssertEqual(KeychainService.map(status: errSecSuccess, data: nil), .notFound)
    }

    func testParse_legacyStringFormat() {
        let legacy = data(#"junk "accessToken":"sk-ant-legacy" more"#)
        XCTAssertEqual(KeychainService.parseAccessToken(from: legacy), "sk-ant-legacy")
    }

    func testParse_rejectsNonAnthropicToken() {
        let json = data(#"{"claudeAiOauth":{"accessToken":"nope"}}"#)
        XCTAssertNil(KeychainService.parseAccessToken(from: json))
    }
}
