import XCTest
@testable import better_mac

final class VolumeKeyDecodingTests: XCTestCase {
    /// Pack like a real NSSystemDefined data1: keyCode in upper 16 bits,
    /// state byte in 0xFF00, repeat count in 0xFF.
    private func encode(keyCode: Int, state: Int, repeatCount: Int = 0) -> Int {
        let flags = ((state & 0xFF) << 8) | (repeatCount & 0xFF)
        return ((keyCode & 0xFFFF) << 16) | (flags & 0xFFFF)
    }

    func testVolumeUpPressedDecodes() {
        let data1 = encode(keyCode: 0, state: 0xA)
        XCTAssertEqual(
            VolumeKeyInterceptor.decode(eventData1: data1),
            .init(key: .volumeUp, state: .pressed)
        )
    }

    func testVolumeDownPressedDecodes() {
        let data1 = encode(keyCode: 1, state: 0xA)
        XCTAssertEqual(
            VolumeKeyInterceptor.decode(eventData1: data1),
            .init(key: .volumeDown, state: .pressed)
        )
    }

    func testMutePressedDecodes() {
        let data1 = encode(keyCode: 7, state: 0xA)
        XCTAssertEqual(
            VolumeKeyInterceptor.decode(eventData1: data1),
            .init(key: .mute, state: .pressed)
        )
    }

    func testVolumeUpReleasedDecodes() {
        let data1 = encode(keyCode: 0, state: 0xB)
        XCTAssertEqual(
            VolumeKeyInterceptor.decode(eventData1: data1),
            .init(key: .volumeUp, state: .released)
        )
    }

    func testRepeatCountIsIgnored() {
        // Auto-repeat events have a non-zero repeat counter in the low byte
        // but should still decode as pressed.
        let data1 = encode(keyCode: 0, state: 0xA, repeatCount: 0x1F)
        XCTAssertEqual(
            VolumeKeyInterceptor.decode(eventData1: data1),
            .init(key: .volumeUp, state: .pressed)
        )
    }

    func testUnknownKeyCodeReturnsNil() {
        let data1 = encode(keyCode: 2, state: 0xA)
        XCTAssertNil(VolumeKeyInterceptor.decode(eventData1: data1))
    }

    func testUnknownStateReturnsNil() {
        let data1 = encode(keyCode: 0, state: 0x0)
        XCTAssertNil(VolumeKeyInterceptor.decode(eventData1: data1))
    }
}
