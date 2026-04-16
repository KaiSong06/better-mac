import AppKit
import Combine
import Foundation

/// Snapshot of the currently playing track, surfaced to SwiftUI. Combines
/// MediaRemote system-wide info with a Spotify AppleScript fallback when
/// MediaRemote is silent.
@MainActor
final class NowPlayingStore: ObservableObject {
    // Public state
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var album: String?
    @Published private(set) var artworkImage: NSImage?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var sourceBundleID: String?

    /// True when we have enough info to show a real track (non-empty title).
    var hasTrack: Bool {
        guard let title, !title.isEmpty else { return false }
        return true
    }

    private let bridge: MediaRemoteBridge
    private let spotify: SpotifyAppleScriptClient

    // Silence detection for Spotify fallback
    private var lastRemoteUpdate: Date = .distantPast
    private var fallbackTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0
    private let fallbackInterval: TimeInterval = 1.0

    init(bridge: MediaRemoteBridge, spotify: SpotifyAppleScriptClient) {
        self.bridge = bridge
        self.spotify = spotify
    }

    func start() {
        bridge.onInfoChanged = { [weak self] info in
            self?.apply(remoteInfo: info)
        }
        bridge.onApplicationChanged = { [weak self] in
            self?.bridge.refresh()
        }
        // Kick off Spotify fallback polling — it no-ops when MediaRemote is fresh.
        scheduleFallbackTimer()
    }

    // MARK: - Commands

    func play() { bridge.play() }
    func pause() { bridge.pause() }

    func toggle() {
        if isPlaying { bridge.pause() } else { bridge.play() }
        bridge.toggle()
    }

    func next() { bridge.nextTrack() }
    func previous() { bridge.previousTrack() }

    func seek(to seconds: TimeInterval) {
        bridge.seek(to: seconds)
        elapsed = min(max(seconds, 0), duration > 0 ? duration : seconds)
    }

    // MARK: - Parsing helpers (exposed internal for unit tests)

    func apply(remoteInfo info: [String: Any]) {
        // Empty dict means no active source → let fallback decide what to do.
        guard !info.isEmpty else {
            return
        }
        lastRemoteUpdate = Date()

        if let t = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !t.isEmpty {
            title = t
        }
        if let a = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String {
            artist = a
        }
        if let a = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String {
            album = a
        }
        if let d = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double, d > 0 {
            duration = d
        }
        if let e = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double {
            let d = duration > 0 ? duration : e
            elapsed = min(max(e, 0), d)
        }
        if let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
            isPlaying = rate > 0.0
        }
        if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
           let image = NSImage(data: data) {
            artworkImage = image
        }
        if let bundle = info["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] as? Data {
            // The framework sometimes ships the client bundle ID inside a
            // proto blob. We try to extract a bundle ID if present, else
            // leave sourceBundleID alone.
            if let s = String(data: bundle, encoding: .utf8), s.contains(".") {
                sourceBundleID = Self.extractBundleID(from: s) ?? sourceBundleID
            }
        }
    }

    func apply(spotify track: SpotifyTrack) {
        title = track.name
        artist = track.artist
        album = track.album
        duration = track.duration
        elapsed = min(max(track.elapsed, 0), track.duration)
        isPlaying = true
        sourceBundleID = "com.spotify.client"
        if let art = track.artwork {
            artworkImage = art
        }
    }

    // MARK: - Fallback timer

    private func scheduleFallbackTimer() {
        fallbackTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: fallbackInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fallbackTick()
            }
        }
        timer.tolerance = 0.25
        fallbackTimer = timer
    }

    private func fallbackTick() async {
        let silent = Date().timeIntervalSince(lastRemoteUpdate) >= silenceThreshold
        guard silent else { return }
        guard spotify.isSpotifyRunning() else { return }
        if let track = await spotify.fetch() {
            Log.spotify.debug("Spotify fallback engaged")
            apply(spotify: track)
        }
    }

    // MARK: - Helpers

    private static func extractBundleID(from haystack: String) -> String? {
        // Very conservative: look for a plausible reverse-DNS chunk.
        let pattern = /[a-zA-Z0-9\-_]+(?:\.[a-zA-Z0-9\-_]+){1,4}/
        return haystack.firstMatch(of: pattern).map { String($0.0) }
    }
}
