import AppKit
import CoreGraphics
import Foundation

/// Intercepts hardware volume up/down/mute keys via a CGEventTap and:
///  1. Applies the volume change via CoreAudio on the current output device.
///  2. Returns `nil` from the callback so the OS never sees the event and
///     therefore never shows the native macOS HUD.
///  3. Notifies the HUD controller to render the iPhone-style pill.
///
/// Requires Accessibility permission to install the event tap.
@MainActor
final class VolumeKeyInterceptor {
    enum Key: Equatable {
        case volumeUp
        case volumeDown
        case mute

        static func from(keyCode: Int) -> Key? {
            switch keyCode {
            case 0: return .volumeUp
            case 1: return .volumeDown
            case 7: return .mute
            default: return nil
            }
        }
    }

    enum KeyState: Equatable {
        case pressed
        case released

        /// `flags` is the lower 16 bits of an NSSystemDefined data1. The
        /// state byte lives in the upper 8 bits (`0xA` pressed, `0xB`
        /// released); the lower 8 bits are a repeat counter we ignore.
        static func from(flags: Int) -> KeyState? {
            let state = (flags & 0xFF00) >> 8
            switch state {
            case 0xA: return .pressed
            case 0xB: return .released
            default: return nil
            }
        }
    }

    struct Decoded: Equatable {
        let key: Key
        let state: KeyState
    }

    private let audio: AudioOutputMonitor
    private let onPressed: () -> Void
    private let step: Float = 1.0 / 16.0

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Debounce frequent key repeats so we don't hammer CoreAudio.
    private var lastAdjust: Date = .distantPast
    private let minInterval: TimeInterval = 0.016

    init(audio: AudioOutputMonitor, onPressed: @escaping () -> Void) {
        self.audio = audio
        self.onPressed = onPressed
    }

    // MARK: - Lifecycle

    func start() {
        guard tap == nil else { return }
        guard Permissions.isAccessibilityTrusted() else {
            Log.volume.info("Skipping tap install — Accessibility not trusted yet")
            return
        }
        let mask = CGEventMask(1 << 14 /* NSSystemDefined */)
        let this = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<VolumeKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

                // Self-heal if the tap gets disabled.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    Task { @MainActor in me.reenable() }
                    return Unmanaged.passUnretained(event)
                }

                // CGEvent doesn't give us subtype/data directly, so lean on
                // NSEvent to decode the systemDefined event.
                guard let ns = NSEvent(cgEvent: event) else {
                    return Unmanaged.passUnretained(event)
                }
                guard ns.type == .systemDefined, ns.subtype.rawValue == 8 else {
                    return Unmanaged.passUnretained(event)
                }
                guard let decoded = VolumeKeyInterceptor.decode(eventData1: ns.data1) else {
                    return Unmanaged.passUnretained(event)
                }

                Task { @MainActor in
                    me.handle(decoded)
                }
                // Consume the event so the OS HUD never fires.
                return nil
            },
            userInfo: this
        ) else {
            Log.volume.error("CGEvent.tapCreate returned nil — accessibility likely missing")
            return
        }

        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.tap = port
        self.runLoopSource = source
        Log.volume.info("Volume key interceptor active")
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    /// Re-enables the tap after timeout / sleep events. Safe to call when
    /// the tap is already enabled or when it doesn't exist yet.
    func reenable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            start()
        }
    }

    // MARK: - Handling

    private func handle(_ decoded: Decoded) {
        guard decoded.state == .pressed else { return }
        let now = Date()
        if now.timeIntervalSince(lastAdjust) < minInterval { return }
        lastAdjust = now

        switch decoded.key {
        case .volumeUp:
            // Pressing volume up while muted should unmute and restore the
            // prior volume (which CoreAudio preserves across the mute toggle)
            // before applying the step. Matches native macOS behaviour.
            if audio.isMuted { audio.setMuted(false) }
            audio.adjustVolume(by: step)
        case .volumeDown:
            if audio.isMuted { audio.setMuted(false) }
            audio.adjustVolume(by: -step)
        case .mute:
            audio.toggleMute()
        }
        onPressed()
    }

    // MARK: - Pure decoder (for tests)

    nonisolated static func decode(eventData1 data1: Int) -> Decoded? {
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        guard let key = Key.from(keyCode: keyCode),
              let state = KeyState.from(flags: keyFlags) else {
            return nil
        }
        return Decoded(key: key, state: state)
    }
}
