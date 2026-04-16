import AppKit
import Foundation

struct SpotifyTrack: Equatable {
    let name: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsed: TimeInterval
    let artworkURL: URL?
    var artwork: NSImage?

    static func == (lhs: SpotifyTrack, rhs: SpotifyTrack) -> Bool {
        lhs.name == rhs.name &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.duration == rhs.duration &&
        lhs.elapsed == rhs.elapsed &&
        lhs.artworkURL == rhs.artworkURL
    }
}

/// Dedicated Spotify fallback. Only used when MediaRemote goes silent while
/// Spotify is running.
@MainActor
final class SpotifyAppleScriptClient {
    private(set) var unavailable: Bool = false

    func isSpotifyRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }

    func fetch() async -> SpotifyTrack? {
        guard !unavailable else { return nil }
        guard isSpotifyRunning() else { return nil }

        guard let raw = runScript() else { return nil }
        guard let parsed = Self.parse(output: raw) else { return nil }

        if let url = parsed.artworkURL {
            if let image = await loadArtwork(url: url) {
                var t = parsed
                t.artwork = image
                return t
            }
        }
        return parsed
    }

    // MARK: - AppleScript

    private let script = """
    tell application "Spotify"
        if player state is playing then
            set n to name of current track
            set a to artist of current track
            set al to album of current track
            set d to duration of current track
            set p to player position
            set au to artwork url of current track
            return n & "\t" & a & "\t" & al & "\t" & d & "\t" & p & "\t" & au
        else
            return ""
        end if
    end tell
    """

    private func runScript() -> String? {
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { return nil }
        let descriptor = apple.executeAndReturnError(&error)
        if let error {
            let code = (error["NSAppleScriptErrorNumber"] as? Int) ?? 0
            if code == -1743 /* errAEEventNotPermitted */ {
                Log.spotify.error("AppleScript permission denied; disabling fallback")
                unavailable = true
            } else {
                Log.spotify.debug("AppleScript error: \(error, privacy: .public)")
            }
            return nil
        }
        return descriptor.stringValue
    }

    private func loadArtwork(url: URL) async -> NSImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            Log.spotify.debug("Artwork fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Parsing (exposed internal for unit tests)

    /// Parse the tab-separated string produced by `script`.
    /// Format: name\tartist\talbum\tduration_ms\tposition_seconds\tartwork_url
    nonisolated static func parse(output: String) -> SpotifyTrack? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let parts = trimmed.components(separatedBy: "\t")
        guard parts.count >= 6 else { return nil }
        let name = parts[0]
        let artist = parts[1]
        let album = parts[2]
        // Spotify's duration is reported in milliseconds.
        let durationMS = Double(parts[3]) ?? 0
        let duration = durationMS / 1000.0
        let elapsed = Double(parts[4]) ?? 0
        let url = URL(string: parts[5])
        return SpotifyTrack(
            name: name,
            artist: artist,
            album: album,
            duration: max(0, duration),
            elapsed: max(0, min(elapsed, duration)),
            artworkURL: url,
            artwork: nil
        )
    }
}
