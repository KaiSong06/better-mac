import XCTest
@testable import better_mac

final class SeekBarMathTests: XCTestCase {
    func testHalfWayReturnsHalfDuration() {
        let t = SeekBarMath.elapsed(forLocalX: 100, width: 200, duration: 240)
        XCTAssertEqual(t, 120, accuracy: 0.001)
    }

    func testClampedToZero() {
        let t = SeekBarMath.elapsed(forLocalX: -50, width: 200, duration: 240)
        XCTAssertEqual(t, 0)
    }

    func testClampedToDuration() {
        let t = SeekBarMath.elapsed(forLocalX: 999, width: 200, duration: 240)
        XCTAssertEqual(t, 240, accuracy: 0.001)
    }

    func testZeroDurationYieldsZero() {
        let t = SeekBarMath.elapsed(forLocalX: 50, width: 200, duration: 0)
        XCTAssertEqual(t, 0)
    }

    func testProgress() {
        XCTAssertEqual(SeekBarMath.progress(elapsed: 60, duration: 240), 0.25)
        XCTAssertEqual(SeekBarMath.progress(elapsed: 300, duration: 240), 1.0)
        XCTAssertEqual(SeekBarMath.progress(elapsed: -10, duration: 240), 0.0)
    }
}
