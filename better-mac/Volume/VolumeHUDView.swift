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
    // derives its panel size from these + the shadow margins below so the
    // drop shadow has room to render without clipping.
    static let pillSize = CGSize(width: 56, height: 200)
    // Horizontal shadow reach = shadowRadius (20) on the left. The right
    // side gets its shadow room from `edgeInsetFromScreen` below instead,
    // since the pill is inset from the screen edge rather than flush.
    static let shadowMarginH: CGFloat = 20
    // Vertical shadow reach = shadowRadius (20) + abs(shadow y offset 4) = 24
    // on both top and bottom.
    static let shadowMarginV: CGFloat = 24
    // Gap between the pill's right edge and the screen's right edge. Also
    // doubles as right-side shadow clearance — the shadow (radius 20)
    // bleeds into this padding and then clips at the panel boundary.
    static let edgeInsetFromScreen: CGFloat = 16

    // Single source of truth for the fill/mask animation so the two layers
    // cannot drift if the spring is retuned.
    static let volumeSpring: Animation = .spring(response: 0.38, dampingFraction: 0.86)

    private var clampedVolume: CGFloat {
        CGFloat(max(0, min(1, volume)))
    }

    private var fillFraction: CGFloat {
        muted ? 0 : clampedVolume
    }

    var body: some View {
        let fillH = Self.pillSize.height * fillFraction
        // iOS proportions: icon ~46% of pill width, ~22% bottom padding.
        let iconSize = Self.pillSize.width * 0.46
        let iconBottom = Self.pillSize.width * 0.22

        ZStack(alignment: .bottom) {
            // Track — lighter vibrancy material so the pill tints / blurs
            // whatever sits behind the HUD panel. `.thinMaterial` reads
            // lighter than `.regularMaterial` while still giving the
            // frosted iOS look.
            Capsule(style: .continuous)
                .fill(.thinMaterial)

            // Fill — pure white, grows from the bottom. The outer clipShape
            // tapers the fill's bottom with the pill's curve. Spring tuned
            // to iOS feel: responsive lead with a gentle settle.
            Rectangle()
                .fill(Color.white)
                .frame(height: fillH)
                .animation(Self.volumeSpring, value: fillH)

            // Icon layer — differential inversion.
            // White glyph is always drawn; the black glyph overlays only in
            // the bottom `fillH` region, so the glyph reads as inverted
            // wherever the white fill sits behind it. Both icons share the
            // same position, so the inversion boundary is pixel-exact as the
            // fill animates. The mask Rectangle carries its own explicit
            // spring keyed on fillH so it stays locked to the fill even
            // without an ambient withAnimation transaction.
            //
            // `variableValue: iconVariableValue` makes the speaker glyph a
            // single variable symbol (speaker.wave.3.fill) whose wave bars
            // fill as volume rises — same bounding box at every level, so
            // the icon doesn't visibly grow/shrink the way
            // speaker.wave.N.fill variants did. Non-variable glyphs
            // (airpods, headphones, airplayaudio, speaker.slash.fill)
            // ignore the parameter. `.symbolRenderingMode(.monochrome)`
            // pins every glyph to the single foreground color so the
            // multi-element symbols (airpods, headphones) don't render
            // with hierarchical tone variation.
            ZStack {
                Image(systemName: iconName, variableValue: iconVariableValue)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                    .frame(width: iconSize, height: iconSize)
                    .padding(.bottom, iconBottom)
                    // Outer frame expands to the pill bounds so
                    // `.alignment: .bottom` pins the icon to the pill,
                    // not to its own bounding box.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                Image(systemName: iconName, variableValue: iconVariableValue)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.black)
                    .frame(width: iconSize, height: iconSize)
                    .padding(.bottom, iconBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .mask(
                        Rectangle()
                            .frame(height: fillH)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .animation(Self.volumeSpring, value: fillH)
                    )
            }
        }
        .frame(width: Self.pillSize.width, height: Self.pillSize.height)
        .clipShape(Capsule(style: .continuous))
        // Softer, larger shadow matches iOS elevation.
        .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 4)
        // Trailing alignment inside the host panel, with `edgeInsetFromScreen`
        // of padding on the right. The panel's right edge sits at the
        // screen edge; the pill sits `edgeInsetFromScreen` pt inside that.
        // The padding also provides right-side shadow bleed room so the
        // shadow fades smoothly into the gap rather than clipping hard.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, Self.edgeInsetFromScreen)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    // MARK: - Symbol resolution

    /// SF Symbol name for the active output. Speaker-type outputs always
    /// use `speaker.wave.3.fill` — a variable symbol whose wave count is
    /// driven by `iconVariableValue`, so the glyph's bounding box stays
    /// constant regardless of volume level (the `speaker.wave.N.fill`
    /// family we used before rendered at subtly different sizes per N).
    private var iconName: String {
        if muted { return "speaker.slash.fill" }
        switch kind {
        case .airPods:           return "airpods"
        case .builtInHeadphones: return "headphones"
        case .airPlay:           return "airplayaudio"
        case .builtInSpeakers,
             .usb,
             .bluetooth,
             .other:             return "speaker.wave.3.fill"
        }
    }

    /// Variable-symbol fill level, applied to `speaker.wave.3.fill` so the
    /// wave bars fill as volume rises. Non-variable glyphs (airpods,
    /// headphones, airplayaudio, speaker.slash.fill) ignore this value.
    private var iconVariableValue: Double {
        muted ? 0 : Double(clampedVolume)
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
