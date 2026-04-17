import SwiftUI

/// iPhone-style volume capsule.
///
/// - **Track**: translucent vibrancy material (`.regularMaterial`) so the pill
///   blurs whatever's behind the HUD window, matching iOS's frosted look.
/// - **Fill**: white rectangle growing from the bottom, clipped to the
///   capsule outline.
/// - **Icon**: rendered twice at the same position — white over the track and
///   black over the fill — so the glyph inverts color across the fill boundary
///   in lock-step with the fill height.
/// - **Layout**: the pill is a fixed 56×200 aligned to the trailing edge of
///   the host container (which is 72×232 in production) so it sits flush with
///   the screen's right edge while leaving shadow room on the other three sides.
struct VolumeHUDView: View {
    let volume: Float          // 0.0 ... 1.0
    let muted: Bool
    let kind: OutputKind
    let deviceName: String
    let showPercentage: Bool

    // Visible pill size. The hosting container (see VolumeHUDWindowController)
    // is larger so the shadow has room to render on left/top/bottom.
    private let pillWidth: CGFloat = 56
    private let pillHeight: CGFloat = 200

    private var clampedVolume: CGFloat {
        CGFloat(max(0, min(1, volume)))
    }

    private var fillFraction: CGFloat {
        muted ? 0 : clampedVolume
    }

    var body: some View {
        let fillH = pillHeight * fillFraction
        // iOS proportions: icon ~46% of pill width, ~22% bottom padding.
        let iconSize = pillWidth * 0.46
        let iconBottom = pillWidth * 0.22

        ZStack(alignment: .bottom) {
            // Track — vibrancy material so the pill tints / blurs whatever
            // sits behind the HUD panel (wallpaper, other windows).
            Capsule(style: .continuous)
                .fill(.regularMaterial)

            // Fill — pure white, grows from the bottom. The outer clipShape
            // tapers the fill's bottom with the pill's curve. Spring tuned
            // to iOS feel: responsive lead with a gentle settle.
            Rectangle()
                .fill(Color.white)
                .frame(height: fillH)
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.86),
                    value: fillH
                )

            // Icon layer — differential inversion.
            // White glyph is always drawn; the black glyph overlays only in
            // the bottom `fillH` region, so the glyph reads as inverted
            // wherever the white fill sits behind it. Both icons share the
            // same position, so the inversion boundary is pixel-exact as the
            // fill animates.
            ZStack {
                Image(systemName: iconName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: iconSize, height: iconSize)
                    .padding(.bottom, iconBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                Image(systemName: iconName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.black)
                    .frame(width: iconSize, height: iconSize)
                    .padding(.bottom, iconBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .mask(
                        Rectangle()
                            .frame(height: fillH)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    )
            }
        }
        .frame(width: pillWidth, height: pillHeight)
        .clipShape(Capsule(style: .continuous))
        // Softer, larger shadow matches iOS elevation.
        .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 4)
        // Trailing alignment inside the larger host so the pill hugs the
        // right edge of the screen while the shadow has room on the other
        // three sides.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    // MARK: - Symbol resolution

    /// SF Symbol name for the active output. For speaker-type outputs the
    /// glyph is chosen from the `speaker.wave.N.fill` family so the number
    /// of wave bars tracks the current level — matching iOS's volume HUD.
    private var iconName: String {
        if muted { return "speaker.slash.fill" }
        switch kind {
        case .airPods:           return "airpods"
        case .builtInHeadphones: return "headphones"
        case .airPlay:           return "airplayaudio"
        case .builtInSpeakers,
             .usb,
             .bluetooth,
             .other:             return speakerSymbolForLevel
        }
    }

    private var speakerSymbolForLevel: String {
        if clampedVolume <= 0.001 { return "speaker.fill" }
        if clampedVolume <= 0.33  { return "speaker.wave.1.fill" }
        if clampedVolume <= 0.66  { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
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
        .frame(width: 72, height: 232)
        .padding()
        .background(Color.gray)
}

#Preview("30%") {
    VolumeHUDView(volume: 0.3, muted: false, kind: .builtInSpeakers, deviceName: "Speakers", showPercentage: false)
        .frame(width: 72, height: 232)
        .padding()
        .background(Color.gray)
}

#Preview("Muted") {
    VolumeHUDView(volume: 0.7, muted: true, kind: .builtInSpeakers, deviceName: "Speakers", showPercentage: false)
        .frame(width: 72, height: 232)
        .padding()
        .background(Color.gray)
}
#endif
