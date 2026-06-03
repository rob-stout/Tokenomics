import XCTest
@testable import Tokenomics

/// Regression test for the popover tab-bar overflow fix.
///
/// The old behavior scrolled on a hard count (`> 6`), which mis-fired for mid
/// counts that actually fit — leaving dead space at the end of the bar. The bar
/// now scrolls only when measured content genuinely overflows the available
/// width. This exercises that pure decision.
@MainActor
final class BrandTabScrollTests: XCTestCase {

    func testDoesNotScrollBeforeMeasurement() {
        // availableWidth == 0 means "not measured yet" → render the fill layout.
        XCTAssertFalse(BrandTabView.needsScroll(contentWidth: 500, availableWidth: 0))
    }

    func testDoesNotScrollWhenContentFits() {
        XCTAssertFalse(BrandTabView.needsScroll(contentWidth: 300, availableWidth: 400))
    }

    func testDoesNotScrollWhenExactlyEqual() {
        // Equal widths fit — only a true overflow scrolls.
        XCTAssertFalse(BrandTabView.needsScroll(contentWidth: 400, availableWidth: 400))
    }

    func testScrollsWhenContentOverflows() {
        XCTAssertTrue(BrandTabView.needsScroll(contentWidth: 500, availableWidth: 400))
    }
}
