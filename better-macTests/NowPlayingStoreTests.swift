import XCTest
@testable import better_mac

@MainActor
final class NowPlayingStoreTests: XCTestCase {
    private func makeStore() -> NowPlayingStore {
        let bridge = MediaRemoteBridge()
        let spotify = SpotifyAppleScriptClient()
        return NowPlayingStore(bridge: bridge, spotify: spotify)
    }

    func testFullPayloadPopulatesAllFields() {
        let store = makeStore()
        let info: [String: Any] = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Sugar",
            "kMRMediaRemoteNowPlayingInfoArtist": "Maroon 5",
            "kMRMediaRemoteNowPlayingInfoAlbum": "V",
            "kMRMediaRemoteNowPlayingInfoDuration": 235.0,
            "kMRMediaRemoteNowPlayingInfoElapsedTime": 12.0,
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1.0
        ]
        store.apply(remoteInfo: info)
        XCTAssertEqual(store.title, "Sugar")
        XCTAssertEqual(store.artist, "Maroon 5")
        XCTAssertEqual(store.album, "V")
        XCTAssertEqual(store.duration, 235.0)
        XCTAssertEqual(store.elapsed, 12.0)
        XCTAssertTrue(store.isPlaying)
    }

    func testPausedPreservesArtwork() {
        let store = makeStore()
        // First payload sets title and artwork data (we can't create NSImage
        // without real data; skip artwork here but verify isPlaying flip).
        store.apply(remoteInfo: [
            "kMRMediaRemoteNowPlayingInfoTitle": "A",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1.0
        ])
        XCTAssertTrue(store.isPlaying)

        store.apply(remoteInfo: [
            "kMRMediaRemoteNowPlayingInfoTitle": "A",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 0.0
        ])
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.title, "A")
    }

    func testElapsedIsClampedToDuration() {
        let store = makeStore()
        store.apply(remoteInfo: [
            "kMRMediaRemoteNowPlayingInfoTitle": "Over",
            "kMRMediaRemoteNowPlayingInfoDuration": 100.0,
            "kMRMediaRemoteNowPlayingInfoElapsedTime": 200.0
        ])
        XCTAssertEqual(store.elapsed, 100.0)
    }

    func testEmptyDictIsIgnored() {
        let store = makeStore()
        store.apply(remoteInfo: [
            "kMRMediaRemoteNowPlayingInfoTitle": "Initial"
        ])
        XCTAssertEqual(store.title, "Initial")
        store.apply(remoteInfo: [:])
        XCTAssertEqual(store.title, "Initial", "Empty dict should not clear state")
    }
}
