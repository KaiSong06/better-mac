import XCTest
@testable import better_mac

final class VolumeKeyDecodingTests: XCTestCase {
    private func encode(keyCode: Int, flags: Int) -> Int {
        return ((keyCode & 0xFFFF) << 16) | (flags & 0xFFFF)
    }

    func testVolumeUpPressedDecodes() {
        let data1 = encode(keyCode: 0, flags: 0xA)
        XCTAssertEqual(
            VolumeKeyInterceptor.decode(eventData1: data1),
            .init(key: .volumeUp, state: .pressed)
        )
    }

    func testVolumeDownPressedDecodes() {
        let data1 = encode(keyCode: 1, flags: 0xA)
        XCTAssertEqual(
            VolumeKeyInterceptor.decode(eventData1: data1),
            .init(key: .volumeDown, state: .pressed)
        )
    }

    func testMutePressedDecodes() {
        let data1 = encode(keyCode: 7, flags: 0xA)
        XCTAssertEqual(
            VolumeKeyInterceptor.decode(eventData1: data1),
            .init(key: .mute, state: .pressed)
        )
    }

    func testVolumeUpReleasedDecodes() {
        let data1 = encode(keyCode: 0, flags: 0xB)
        XCTAssertEqual(
            VolumeKeyInterceptor.decode(eventData1: data1),
            .init(key: .volumeUp, state: .released)
        )
    }

    func testUnknownKeyCodeReturnsNil() {
        let data1 = encode(keyCode: 2, flags: 0xA)
        XCTAssertNil(VolumeKeyInterceptor.decode(eventData1: data1))
    }

    func testUnknownFlagsReturnNil() {
        let data1 = encode(keyCode: 0, flags: 0x0)
        XCTAssertNil(VolumeKeyInterceptor.decode(eventData1: data1))
    }
}
