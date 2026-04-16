import SwiftUI

/// iPhone-style vertical volume pill showing the active output device, its
/// icon, and a bottom-up filling bar.
struct VolumeHUDView: View {
    let volume: Float          // 0.0 ... 1.0
    let muted: Bool
    let kind: OutputKind
    let deviceName: String
    let showPercentage: Bool

    var body: some View {
        ZStack {
            // Glass-like pill background. We stick with ultraThinMaterial on
            // dark for an iOS-flavored look without going pure black.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 4)

            VStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(height: 22)

                Text(deviceName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)

                verticalBar

                if showPercentage {
                    Text("\(Int((volume * 100).rounded()))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
        }
    }

    private var verticalBar: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let clamped = max(0, min(1, CGFloat(volume)))
            let fillHeight = muted ? 0 : height * clamped
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.primary.opacity(0.85))
                    .frame(height: fillHeight)
                    .animation(.easeOut(duration: 0.12), value: volume)
                    .animation(.easeOut(duration: 0.12), value: muted)
            }
        }
        .frame(width: 10)
    }

    var iconName: String {
        if muted { return "speaker.slash.fill" }
        switch kind {
        case .airPods: return "airpods"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .builtInHeadphones: return "headphones"
        case .builtInSpeakers:
            return speakerIcon(for: volume)
        case .usb: return "speaker.wave.2.fill"
        case .airPlay: return "airplayaudio"
        case .other: return speakerIcon(for: volume)
        }
    }

    private func speakerIcon(for volume: Float) -> String {
        if volume <= 0.001 { return "speaker.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
