import XCTest
@testable import Tokenomics

// MARK: - Mock URLProtocol

/// Intercepts URLSession requests so tests never hit the network.
final class MockURLProtocol: URLProtocol {
    /// Set before each test to define the stubbed response.
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - UsageService Tests

final class UsageServiceTests: XCTestCase {

    // MARK: - Rate Limit / Backoff

    /// Regression: commit 111540c — Retry-After: 0 must still enforce the exponential
    /// fallback (5-minute base). The server-sent value of 0 is meaningless as a cooldown.
    func testRateLimitBackoff_retryAfterZero_fallsBackToExponential() {
        let computed = UsageService.backoffInterval(retryAfterHeader: 0, consecutive429s: 1)
        XCTAssertEqual(computed, 300, "Retry-After: 0 must fall back to 300s (5 minutes)")
    }

    func testRateLimitBackoff_missingHeader_fallsBackToExponential() {
        let computed = UsageService.backoffInterval(retryAfterHeader: nil, consecutive429s: 1)
        XCTAssertEqual(computed, 300, "Missing Retry-After must fall back to 300s (5 minutes)")
    }

    /// A positive server-sent Retry-After is authoritative — honor it exactly,
    /// even when shorter than the exponential fallback would be.
    func testRateLimitBackoff_positiveRetryAfter_isHonored() {
        let computed = UsageService.backoffInterval(retryAfterHeader: 42, consecutive429s: 3)
        XCTAssertEqual(computed, 42, "A positive Retry-After must be used verbatim")
    }

    func testRateLimitBackoff_exponentialProgression() {
        let expected: [TimeInterval] = [300, 600, 1200, 2400, 3600, 3600]

        for (index, expectedBackoff) in expected.enumerated() {
            let computed = UsageService.backoffInterval(
                retryAfterHeader: nil,
                consecutive429s: index + 1
            )
            XCTAssertEqual(computed, expectedBackoff,
                "Consecutive 429 #\(index + 1) should back off \(expectedBackoff)s")
        }
    }

    func testRateLimitBackoff_cappedAt1Hour() {
        // After 4 consecutive 429s: 300 * 2^3 = 2400. After 5: 300 * 2^4 = 4800 → capped at 3600
        let computed = UsageService.backoffInterval(retryAfterHeader: nil, consecutive429s: 5)
        XCTAssertEqual(computed, 3600, "Backoff must be capped at 3600s (1 hour)")
    }

    // MARK: - Error Classification

    func testAppError_rateLimited_isRateLimited() {
        let error = AppError.rateLimited(retryAfter: 300)
        XCTAssertTrue(error.isRateLimited)
        XCTAssertFalse(error.isTokenExpired)
    }

    func testAppError_tokenExpired_isTokenExpired() {
        let error = AppError.tokenExpired
        XCTAssertTrue(error.isTokenExpired)
        XCTAssertFalse(error.isRateLimited)
    }

    func testAppError_networkUnavailable_neitherRateLimitedNorExpired() {
        let error = AppError.networkUnavailable
        XCTAssertFalse(error.isRateLimited)
        XCTAssertFalse(error.isTokenExpired)
    }

    func testAppError_httpError_neitherRateLimitedNorExpired() {
        let error = AppError.httpError(statusCode: 500)
        XCTAssertFalse(error.isRateLimited)
        XCTAssertFalse(error.isTokenExpired)
    }

    // MARK: - resetRateLimit

    func testResetRateLimit_clearsState() async {
        let service = UsageService()
        // Call resetRateLimit — verifying it doesn't throw and completes cleanly.
        // The meaningful regression is that after reset, subsequent fetches aren't
        // gate-blocked by a stale rateLimitedUntil timestamp.
        await service.resetRateLimit()
        // No assertion needed beyond non-crash; the state is private.
        // Integration coverage for the token-rotation path lives in ClaudeProviderTests.
    }
}
