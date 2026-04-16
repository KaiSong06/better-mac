import AppKit
import Combine
import CoreAudio
import Foundation

/// Broad categorization of the current audio output used to pick an icon
/// and short label for the HUD.
enum OutputKind: Equatable {
    case builtInSpeakers
    case builtInHeadphones
    case airPods
    case bluetooth
    case usb
    case airPlay
    case other
}

struct OutputSnapshot: Equatable {
    let deviceID: AudioDeviceID
    let displayName: String
    let kind: OutputKind
}

/// Watches the default output device and publishes changes. Also provides
/// helpers to get/set the scalar volume and mute state of the current output.
@MainActor
final class AudioOutputMonitor: ObservableObject {
    @Published private(set) var current: OutputSnapshot = OutputSnapshot(
        deviceID: kAudioObjectUnknown,
        displayName: "Speakers",
        kind: .other
    )

    @Published private(set) var currentVolume: Float = 0.5
    @Published private(set) var isMuted: Bool = false

    private var systemListenerInstalled = false
    private var deviceListenerInstalled = false

    func start() {
        installDefaultOutputListener()
        refreshCurrent()
    }

    // MARK: - Volume

    func setVolume(_ scalar: Float) {
        let id = current.deviceID
        guard id != kAudioObjectUnknown else { return }
        var vol = max(0.0, min(1.0, scalar))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        // Try main element first (stereo master).
        var size = UInt32(MemoryLayout<Float>.size)
        var status = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &vol)
        if status != noErr {
            // Fall back to per-channel for devices without a master control.
            for channel: UInt32 in [1, 2] {
                addr.mElement = channel
                _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &vol)
            }
        }
        currentVolume = vol
    }

    func adjustVolume(by delta: Float) {
        setVolume(currentVolume + delta)
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ on: Bool) {
        let id = current.deviceID
        guard id != kAudioObjectUnknown else { return }
        var value: UInt32 = on ? 1 : 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &value)
        isMuted = on
    }

    // MARK: - Listening

    private func installDefaultOutputListener() {
        guard !systemListenerInstalled else { return }
        systemListenerInstalled = true

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let this = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            DispatchQueue.main
        ) { _, _ in
            let monitor = Unmanaged<AudioOutputMonitor>.fromOpaque(this).takeUnretainedValue()
            Task { @MainActor in
                monitor.refreshCurrent()
            }
        }
        if status != noErr {
            Log.audio.error("AudioObjectAddPropertyListenerBlock failed: \(status)")
        }
    }

    private func refreshCurrent() {
        guard let id = Self.defaultOutputDevice() else { return }
        let name = Self.deviceName(id) ?? "Speakers"
        let transport = Self.transportType(id)
        let dataSource = Self.dataSource(id)
        let kind = Self.classify(name: name, transport: transport, dataSource: dataSource)
        let snapshot = OutputSnapshot(deviceID: id, displayName: name, kind: kind)

        if snapshot != current {
            current = snapshot
            currentVolume = Self.readVolume(id) ?? currentVolume
            isMuted = Self.readMuted(id) ?? isMuted
            Log.audio.info("Output changed → \(name, privacy: .public) [\(String(describing: kind), privacy: .public)]")
        } else {
            currentVolume = Self.readVolume(id) ?? currentVolume
            isMuted = Self.readMuted(id) ?? isMuted
        }
    }

    // MARK: - Classification (exposed internal for unit tests)

    nonisolated static func classify(name: String, transport: UInt32?, dataSource: UInt32?) -> OutputKind {
        let lower = name.lowercased()
        if lower.contains("airpods") { return .airPods }
        if lower.contains("beats") { return .airPods }
        if lower.contains("airplay") { return .airPlay }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            // Headphones-out over the 3.5mm jack reports data source
            // "Headphones" on Macs that still have one.
            if let ds = dataSource {
                // 'hdpn' fourCC for Headphones
                let headphonesFourCC: UInt32 = 0x6864706E
                if ds == headphonesFourCC { return .builtInHeadphones }
            }
            return .builtInSpeakers
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        default:
            return .other
        }
    }

    // MARK: - CoreAudio helpers

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &id
        )
        return status == noErr ? id : nil
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var str: CFString? = nil
        let status = withUnsafeMutablePointer(to: &str) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        if status == noErr, let s = str as String? {
            return s
        }
        return nil
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func dataSource(_ id: AudioDeviceID) -> UInt32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func readVolume(_ id: AudioDeviceID) -> Float? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        var status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &vol)
        if status == noErr { return vol }
        // Try per-channel as a fallback.
        addr.mElement = 1
        status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &vol)
        return status == noErr ? vol : nil
    }

    private static func readMuted(_ id: AudioDeviceID) -> Bool? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return status == noErr ? (value != 0) : nil
    }
}
