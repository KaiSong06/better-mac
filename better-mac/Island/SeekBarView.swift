import SwiftUI

/// Pure mapping used for testing: convert a local x offset within a track of
/// width `width` to an elapsed time scaled against `duration`.
enum SeekBarMath {
    static func elapsed(forLocalX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0, duration > 0 else { return 0 }
        let clamped = min(max(x, 0), width)
        return duration * TimeInterval(clamped / width)
    }

    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
}

struct SeekBarView: View {
    let elapsed: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragElapsed: TimeInterval? = nil
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let currentElapsed = dragElapsed ?? elapsed
            let progress = SeekBarMath.progress(elapsed: currentElapsed, duration: duration)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 3)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: width * progress, height: 3)
                if isHovering || dragElapsed != nil {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .offset(x: max(0, width * progress - 4))
                }
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .onHover { hovering in isHovering = hovering }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragElapsed = SeekBarMath.elapsed(
                            forLocalX: gesture.location.x,
                            width: width,
                            duration: duration
                        )
                    }
                    .onEnded { gesture in
                        let seconds = SeekBarMath.elapsed(
                            forLocalX: gesture.location.x,
                            width: width,
                            duration: duration
                        )
                        dragElapsed = nil
                        onSeek(seconds)
                    }
            )
        }
    }
}
