import AppKit
import Foundation

/// Bridges to the private MediaRemote.framework so we can read system-wide
/// Now Playing info and send playback commands. Uses dlopen + function pointer
/// lookup because MediaRemote has no public Swift headers.
///
/// IMPORTANT: MediaRemote is a private framework. Apple can break this at any
/// time. Callers must tolerate `isAvailable == false`.
@MainActor
final class MediaRemoteBridge {
    typealias NowPlayingInfo = [String: Any]

    struct Commands {
        static let play: Int32 = 0
        static let pause: Int32 = 1
        static let togglePlayPause: Int32 = 2
        static let next: Int32 = 4
        static let previous: Int32 = 5
    }

    // Change callback — called on main actor with a fresh info dict.
    var onInfoChanged: ((NowPlayingInfo) -> Void)?
    var onApplicationChanged: (() -> Void)?

    private(set) var isAvailable: Bool = false
    private var bundle: CFBundle?

    // Function pointer slots
    private var getInfo: (@convention(c) (DispatchQueue, @escaping (NowPlayingInfo) -> Void) -> Void)?
    private var registerForNotifications: (@convention(c) (DispatchQueue) -> Void)?
    private var sendCommand: (@convention(c) (Int32, [AnyHashable: Any]?) -> Bool)?
    private var setElapsed: (@convention(c) (Double) -> Void)?

    func start() {
        guard !isAvailable else { return }
        guard loadFramework() else {
            Log.media.error("MediaRemote framework failed to load")
            return
        }
        isAvailable = true

        // Subscribe to the distributed notifications the framework fires.
        registerForNotifications?(.main)

        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(handleInfoNotification(_:)),
            name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleAppNotification(_:)),
            name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleInfoNotification(_:)),
            name: NSNotification.Name("kMRNowPlayingPlaybackQueueChangedNotification"),
            object: nil
        )

        // Kick an initial fetch.
        refresh()
    }

    // MARK: - Public commands

    func play() { _ = sendCommand?(Commands.play, nil) }
    func pause() { _ = sendCommand?(Commands.pause, nil) }
    func toggle() { _ = sendCommand?(Commands.togglePlayPause, nil) }
    func nextTrack() { _ = sendCommand?(Commands.next, nil) }
    func previousTrack() { _ = sendCommand?(Commands.previous, nil) }

    func seek(to seconds: Double) {
        setElapsed?(seconds)
    }

    func refresh() {
        guard let getInfo else { return }
        getInfo(.main) { [weak self] info in
            Task { @MainActor in
                self?.onInfoChanged?(info)
            }
        }
    }

    // MARK: - Notifications

    @objc private func handleInfoNotification(_ notification: Notification) {
        refresh()
    }

    @objc private func handleAppNotification(_ notification: Notification) {
        Task { @MainActor in
            self.onApplicationChanged?()
            self.refresh()
        }
    }

    // MARK: - dlopen + symbol lookup

    private func loadFramework() -> Bool {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let url = CFURLCreateWithFileSystemPath(
            kCFAllocatorDefault,
            path as CFString,
            .cfurlposixPathStyle,
            true
        ) else { return false }

        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url) else {
            return false
        }
        self.bundle = bundle

        guard CFBundleLoadExecutable(bundle) else {
            Log.media.error("CFBundleLoadExecutable failed for MediaRemote")
            return false
        }

        guard
            let getInfoPtr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
            let registerPtr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString),
            let sendPtr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else {
            Log.media.error("Failed to resolve required MediaRemote symbols")
            return false
        }

        self.getInfo = unsafeBitCast(getInfoPtr, to: (@convention(c) (DispatchQueue, @escaping (NowPlayingInfo) -> Void) -> Void).self)
        self.registerForNotifications = unsafeBitCast(registerPtr, to: (@convention(c) (DispatchQueue) -> Void).self)
        self.sendCommand = unsafeBitCast(sendPtr, to: (@convention(c) (Int32, [AnyHashable: Any]?) -> Bool).self)

        if let setPtr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) {
            self.setElapsed = unsafeBitCast(setPtr, to: (@convention(c) (Double) -> Void).self)
        }

        return true
    }
}
