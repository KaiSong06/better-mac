import XCTest
import CoreAudio
@testable import better_mac

final class AudioOutputMonitorTests: XCTestCase {
    func testBuiltInSpeakers() {
        let kind = AudioOutputMonitor.classify(
            name: "MacBook Pro Speakers",
            transport: kAudioDeviceTransportTypeBuiltIn,
            dataSource: nil
        )
        XCTAssertEqual(kind, .builtInSpeakers)
    }

    func testBuiltInHeadphonesViaDataSource() {
        // 'hdpn' fourCC
        let hdpn: UInt32 = 0x6864706E
        let kind = AudioOutputMonitor.classify(
            name: "External Headphones",
            transport: kAudioDeviceTransportTypeBuiltIn,
            dataSource: hdpn
        )
        XCTAssertEqual(kind, .builtInHeadphones)
    }

    func testAirPodsByName() {
        let kind = AudioOutputMonitor.classify(
            name: "Kai's AirPods Pro",
            transport: kAudioDeviceTransportTypeBluetooth,
            dataSource: nil
        )
        XCTAssertEqual(kind, .airPods)
    }

    func testBeatsTreatedAsAirPods() {
        let kind = AudioOutputMonitor.classify(
            name: "Beats Fit Pro",
            transport: kAudioDeviceTransportTypeBluetooth,
            dataSource: nil
        )
        XCTAssertEqual(kind, .airPods)
    }

    func testGenericBluetooth() {
        let kind = AudioOutputMonitor.classify(
            name: "JBL Flip 5",
            transport: kAudioDeviceTransportTypeBluetooth,
            dataSource: nil
        )
        XCTAssertEqual(kind, .bluetooth)
    }

    func testUSB() {
        let kind = AudioOutputMonitor.classify(
            name: "USB Audio Interface",
            transport: kAudioDeviceTransportTypeUSB,
            dataSource: nil
        )
        XCTAssertEqual(kind, .usb)
    }

    func testAirPlay() {
        let kind = AudioOutputMonitor.classify(
            name: "Living Room TV",
            transport: kAudioDeviceTransportTypeAirPlay,
            dataSource: nil
        )
        XCTAssertEqual(kind, .airPlay)
    }

    func testUnknownTransportFallsBackToOther() {
        let kind = AudioOutputMonitor.classify(
            name: "Some Device",
            transport: nil,
            dataSource: nil
        )
        XCTAssertEqual(kind, .other)
    }
}
