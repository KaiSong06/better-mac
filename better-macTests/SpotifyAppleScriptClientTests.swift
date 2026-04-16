import XCTest
@testable import better_mac

final class SpotifyAppleScriptClientTests: XCTestCase {
    func testParsesSampleOutput() {
        // Spotify returns durations in milliseconds, position in seconds.
        let raw = "Sugar\tMaroon 5\tV\t235000\t12.5\thttps://i.scdn.co/image/abc"
        let track = SpotifyAppleScriptClient.parse(output: raw)
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.name, "Sugar")
        XCTAssertEqual(track?.artist, "Maroon 5")
        XCTAssertEqual(track?.album, "V")
        XCTAssertEqual(track?.duration, 235.0)
        XCTAssertEqual(track?.elapsed, 12.5)
        XCTAssertEqual(track?.artworkURL?.absoluteString, "https://i.scdn.co/image/abc")
    }

    func testEmptyMeansPaused() {
        XCTAssertNil(SpotifyAppleScriptClient.parse(output: ""))
        XCTAssertNil(SpotifyAppleScriptClient.parse(output: "   \n  "))
    }

    func testMalformedReturnsNil() {
        XCTAssertNil(SpotifyAppleScriptClient.parse(output: "only\ttwo"))
    }

    func testElapsedIsClampedToDuration() {
        let raw = "A\tB\tC\t5000\t99\thttps://example.com"
        let track = SpotifyAppleScriptClient.parse(output: raw)
        XCTAssertEqual(track?.duration, 5.0)
        XCTAssertEqual(track?.elapsed ?? -1, 5.0, accuracy: 0.001)
    }
}
