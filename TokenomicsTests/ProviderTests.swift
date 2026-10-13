import XCTest
@testable import Tokenomics

// MARK: - Provider Identity & Display Label Tests

final class ProviderTests: XCTestCase {

    // MARK: - Display Labels

    func testDisplayName_claude_isAnthropic() {
        XCTAssertEqual(ProviderId.claude.displayName, "Anthropic")
    }

    func testDisplayName_copilot_isGitHubCopilot() {
        XCTAssertEqual(ProviderId.copilot.displayName, "GitHub Copilot")
    }

    func testShortLabel_uniquePerProvider() {
        // All short labels must be unique — they appear in menu bar rings
        let labels = ProviderId.allCases.map(\.shortLabel)
        XCTAssertEqual(labels.count, Set(labels).count,
            "Each provider must have a unique short label for menu bar display")
    }

    // MARK: - Platform Categorization

    func testCategory_anthropic_isPlatforms() {
        XCTAssertEqual(ProviderId.claude.category, .platforms,
            "Anthropic must sit in Platforms — its usage pool covers chat, cowork, and code")
    }

    func testCategory_openAI_isCodingTools() {
        XCTAssertEqual(ProviderId.codex.category, .codingTools)
    }

    func testCategory_google_isCodingTools() {
        XCTAssertEqual(ProviderId.gemini.category, .codingTools)
    }

    func testCategory_copilot_isCodingTools() {
        XCTAssertEqual(ProviderId.copilot.category, .codingTools)
    }

    func testCategory_cursor_isCodingTools() {
        XCTAssertEqual(ProviderId.cursor.category, .codingTools)
    }

    // MARK: - Connection State

    func testConnectionState_connected_isConnected() {
        let state = ProviderConnectionState.connected(plan: "Pro")
        XCTAssertTrue(state.isConnected)
    }

    func testConnectionState_notInstalled_isNotConnected() {
        XCTAssertFalse(ProviderConnectionState.notInstalled.isConnected)
    }

    func testConnectionState_needsKeychainAccess_isNotConnected() {
        XCTAssertFalse(ProviderConnectionState.needsKeychainAccess.isConnected)
        XCTAssertEqual(ProviderConnectionState.needsKeychainAccess.statusText, "Keychain access needed")
    }

    func testConnectionState_authExpired_isNotConnected() {
        XCTAssertFalse(ProviderConnectionState.authExpired.isConnected)
    }

    func testConnectionState_installedNoAuth_isNotConnected() {
        XCTAssertFalse(ProviderConnectionState.installedNoAuth.isConnected)
    }

    func testConnectionState_statusText_connected() {
        let state = ProviderConnectionState.connected(plan: "Max")
        XCTAssertEqual(state.statusText, "Max — Connected")
    }

    // MARK: - ProviderId Identity

    func testProviderId_rawValue_roundTrip() {
        for provider in ProviderId.allCases {
            XCTAssertEqual(ProviderId(rawValue: provider.rawValue), provider,
                "rawValue round-trip must work for \(provider.rawValue)")
        }
    }

    func testProviderId_id_equalsRawValue() {
        for provider in ProviderId.allCases {
            XCTAssertEqual(provider.id, provider.rawValue)
        }
    }

    // MARK: - AppError

    func testAppError_errorDescription_notNil() {
        let errors: [AppError] = [
            .notAuthenticated,
            .tokenExpired,
            .rateLimited(retryAfter: 300),
            .networkUnavailable,
            .httpError(statusCode: 503),
            .unexpectedError(underlying: URLError(.timedOut))
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription,
                "Every AppError case must have a non-nil errorDescription for user display")
        }
    }
}
