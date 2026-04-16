import SwiftUI

/// iPhone-style two-tone volume capsule with a device icon at the bottom.
///
/// The pill (track + fill) is drawn in a single `Canvas` so there's no
/// per-layer compositing — that's what was producing the soft halo around
/// the bottom curve. The icon is overlaid as a normal SwiftUI `Image`, which
/// is fine because the Canvas underneath is now a solid opaque shape.
struct VolumeHUDView: View {
    let volume: Float          // 0.0 ... 1.0
    let muted: Bool
    let kind: OutputKind
    let deviceName: String
    let showPercentage: Bool

    private var clampedVolume: CGFloat {
        CGFloat(max(0, min(1, volume)))
    }

    private var fillFraction: CGFloat {
        muted ? 0 : clampedVolume
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fillH = size.height * fillFraction
            ZStack(alignment: .bottom) {
                // Track — the dark backdrop, always full pill.
                Capsule(style: .continuous)
                    .fill(Color(white: 0.28))

                // Fill — a rectangle that grows from the bottom. The parent
                // `clipShape(Capsule)` crops it to the pill's outline, so the
                // fill's bottom tapers with the pill's curve automatically.
                // Rectangle height is a native animatable SwiftUI property,
                // unlike a Canvas draw, so the fill tweens smoothly when
                // `fillFraction` changes — including blending across rapid
                // key repeats thanks to the interruptible spring.
                Rectangle()
                    .fill(Color.white)
                    .frame(height: fillH)
                    .animation(
                        .spring(response: 0.28, dampingFraction: 0.86),
                        value: fillH
                    )

                Image(systemName: iconName)
                    .resizable()
                    .symbolRenderingMode(.monochrome)
                    .scaledToFit()
                    .foregroundStyle(.black)
                    .frame(width: size.width * 0.42, height: size.width * 0.42)
                    .padding(.bottom, size.width * 0.32)
            }
            .clipShape(Capsule(style: .continuous))
            .accessibilityLabel(Text(accessibilityLabel))
        }
    }

    // MARK: - Symbol resolution

    /// SF Symbol name for the active output. Falls back to a generic speaker
    /// glyph for unknown transports so the pill always renders something.
    private var iconName: String {
        if muted { return "speaker.slash.fill" }
        switch kind {
        case .airPods: return "airpods"
        case .builtInHeadphones: return "headphones"
        case .builtInSpeakers: return "speaker.wave.2.fill"
        case .bluetooth: return bluetoothSymbol
        case .usb: return "speaker.wave.2.fill"
        case .airPlay: return "airplayaudio"
        case .other: return "speaker.wave.2.fill"
        }
    }

    /// `bluetooth` SF Symbol exists on macOS 14+ but isn't in every snapshot
    /// of the framework; fall back to a wave glyph if the system can't
    /// resolve it.
    private var bluetoothSymbol: String {
        if NSImage(systemSymbolName: "bluetooth", accessibilityDescription: nil) != nil {
            return "bluetooth"
        }
        return "dot.radiowaves.left.and.right"
    }

    private var accessibilityLabel: String {
        let pct = Int((clampedVolume * 100).rounded())
        if muted { return "\(deviceName) muted" }
        return "\(deviceName) volume \(pct) percent"
    }
}

#if DEBUG
#Preview("70%") {
    VolumeHUDView(volume: 0.7, muted: false, kind: .airPods, deviceName: "AirPods", showPercentage: false)
        .frame(width: 56, height: 220)
        .padding()
        .background(Color.black)
}

#Preview("Muted") {
    VolumeHUDView(volume: 0.7, muted: true, kind: .builtInSpeakers, deviceName: "Speakers", showPercentage: false)
        .frame(width: 56, height: 220)
        .padding()
        .background(Color.black)
}
#endif
