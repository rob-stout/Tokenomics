import XCTest
@testable import Tokenomics

// MARK: - Provider Identity & Display Label Tests

final class ProviderTests: XCTestCase {

    // MARK: - Display Labels

    func testDisplayName_claude_isClaude() {
        XCTAssertEqual(ProviderId.claude.displayName, "Claude Code")
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

    // MARK: - Connection State

    func testConnectionState_connected_isConnected() {
        let state = ProviderConnectionState.connected(plan: "Pro")
        XCTAssertTrue(state.isConnected)
    }

    func testConnectionState_notInstalled_isNotConnected() {
        XCTAssertFalse(ProviderConnectionState.notInstalled.isConnected)
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
