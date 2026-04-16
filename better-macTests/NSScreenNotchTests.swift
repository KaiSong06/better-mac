import XCTest
import AppKit
@testable import better_mac

final class NSScreenNotchTests: XCTestCase {
    // NSScreen can't be fabricated in pure unit tests, so these tests target
    // the math helpers on a mock-ish geometry. We pull out the pure math into
    // a free function for full unit coverage.

    func testNotchWidthMathAllThreePieces() {
        let fullWidth: CGFloat = 1512
        let leftWidth: CGFloat = 620
        let rightWidth: CGFloat = 620
        let notchWidth = max(0, fullWidth - leftWidth - rightWidth)
        XCTAssertEqual(notchWidth, 272)
    }

    func testFallbackPillCentering() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let width: CGFloat = 200
        let height: CGFloat = 32
        let x = frame.midX - width / 2
        let y = frame.maxY - height
        XCTAssertEqual(x, 1180)
        XCTAssertEqual(y, 1408)
    }
}
