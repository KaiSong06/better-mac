import XCTest
@testable import better_mac

final class IslandPlayingRectTests: XCTestCase {
    private let size = CGSize(width: 340, height: 36)

    func test14InchMBPScreen() {
        // 14" MBP logical resolution
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let rect = IslandWindowController.playingRect(in: screen, size: size)
        XCTAssertEqual(rect.width, 340)
        XCTAssertEqual(rect.height, 36)
        XCTAssertEqual(rect.midX, screen.midX)
        XCTAssertEqual(rect.maxY, screen.maxY)
        XCTAssertEqual(rect.minY, screen.maxY - 36)
    }

    func testSmallerScreenStillCenters() {
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let rect = IslandWindowController.playingRect(in: screen, size: size)
        XCTAssertEqual(rect.midX, 640)
        XCTAssertEqual(rect.minX, 640 - 170)
        XCTAssertEqual(rect.maxY, 800)
    }

    func testTopFlushRegardlessOfScreenHeight() {
        // The pill's bottom (minY in AppKit's bottom-origin space) must be
        // exactly `screen.maxY - size.height`. The same contract should hold
        // for any screen height.
        for height in [600, 800, 982, 1440, 2160] {
            let screen = CGRect(x: 0, y: 0, width: 1512, height: CGFloat(height))
            let rect = IslandWindowController.playingRect(in: screen, size: size)
            XCTAssertEqual(rect.maxY, screen.maxY, "top-flush broken at height \(height)")
            XCTAssertEqual(rect.minY, screen.maxY - size.height, "height off at \(height)")
        }
    }

    func testNonZeroOriginScreen() {
        // Multi-display: secondary screen has a non-zero origin.
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let rect = IslandWindowController.playingRect(in: screen, size: size)
        XCTAssertEqual(rect.midX, screen.midX)
        XCTAssertEqual(rect.minX, screen.midX - size.width / 2)
    }
}
