import XCTest
@testable import Tokenomics

final class APIKeyConnectorTests: XCTestCase {

    func testClassify_unauthorizedMeansBadKey() {
        XCTAssertEqual(APIKeyConnector.classify(AppError.tokenExpired), .invalidKey)
        XCTAssertEqual(APIKeyConnector.classify(AppError.notAuthenticated), .invalidKey)
        XCTAssertEqual(APIKeyConnector.classify(AppError.httpError(statusCode: 403)), .invalidKey)
    }

    func testClassify_networkAndServerErrorsAreNotBlamedOnTheKey() {
        XCTAssertEqual(APIKeyConnector.classify(AppError.networkUnavailable), .unreachable)
        XCTAssertEqual(APIKeyConnector.classify(AppError.httpError(statusCode: 500)), .unreachable)
        XCTAssertEqual(APIKeyConnector.classify(URLError(.notConnectedToInternet)), .unreachable)
    }

    /// 429 means the provider authenticated the key and is only throttling.
    func testClassify_rateLimitedMeansKeyWorks() {
        XCTAssertEqual(APIKeyConnector.classify(AppError.rateLimited(retryAfter: 60)), .saved)
    }

    func testSubmitResultMessages() {
        XCTAssertNil(APIKeySubmitResult.saved.message(providerName: "Runway"))
        XCTAssertEqual(APIKeySubmitResult.invalidKey.message(providerName: "Runway"),
                       "That key didn't work. Check it and try again.")
        XCTAssertEqual(APIKeySubmitResult.unreachable.message(providerName: "Runway"),
                       "Couldn't reach Runway to check that key. Check your connection and try again.")
    }

    func testExpiredTokenMessage_isApiKeyWordingOnlyForApiKeyProviders() {
        XCTAssertEqual(AppError.tokenExpired.message(for: .runway),
                       "API key no longer works — update it in Settings → AI Connections.")
        XCTAssertEqual(AppError.tokenExpired.message(for: .stableDiffusion),
                       "API key no longer works — update it in Settings → AI Connections.")
        XCTAssertEqual(AppError.tokenExpired.message(for: .claude),
                       "Session expired — re-authenticate in your terminal, then click Refresh.")
    }
}
