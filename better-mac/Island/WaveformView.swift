import SwiftUI

/// Compact sine-wave visual for the island's playing state.
///
/// When `isAnimating` is true, a `TimelineView(.animation)` ticks a monotonic
/// time source into a `Canvas` that redraws the wave with a phase offset.
/// When false, the view renders the same shape with a fixed phase (zero) and
/// nothing redraws — no CPU while paused.
///
/// Entirely presentational. No test surface — visual behavior is validated
/// in the Unit 4 integration checks.
struct WaveformView: View {
    var isAnimating: Bool = true
    var color: Color = .white
    var amplitudeFraction: CGFloat = 0.30     // fraction of height
    var cyclesAcrossWidth: CGFloat = 1.4      // number of sine cycles that fit across the width
    var phaseSpeed: CGFloat = 2.0             // how fast the phase advances (radians per second)
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation) { context in
                    canvas(phase: phase(at: context.date))
                }
            } else {
                canvas(phase: 0)
            }
        }
    }

    /// Derive a smoothly-advancing phase (in radians) from a timeline date.
    private func phase(at date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        return CGFloat(t) * phaseSpeed
    }

    private func canvas(phase: CGFloat) -> some View {
        Canvas { context, size in
            let height = size.height
            let width = size.width
            guard width > 0, height > 0 else { return }

            let midY = height / 2
            let amplitude = height * amplitudeFraction
            let omega = (2 * .pi * cyclesAcrossWidth) / width

            // Sample the sine at roughly one point per 2 pixels for a smooth
            // curve without overloading the path node count on wide widths.
            let step: CGFloat = 2
            var path = Path()
            var x: CGFloat = 0
            path.move(to: CGPoint(x: 0, y: midY + amplitude * sin(phase)))
            while x <= width {
                let y = midY + amplitude * sin(omega * x + phase)
                path.addLine(to: CGPoint(x: x, y: y))
                x += step
            }
            // Close the final point exactly on the trailing edge so the wave
            // spans full width regardless of whether width is divisible by
            // `step`.
            let finalY = midY + amplitude * sin(omega * width + phase)
            path.addLine(to: CGPoint(x: width, y: finalY))

            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

#if DEBUG
#Preview("Animating") {
    WaveformView()
        .frame(width: 200, height: 20)
        .padding()
        .background(Color.black)
}

#Preview("Frozen") {
    WaveformView(isAnimating: false)
        .frame(width: 200, height: 20)
        .padding()
        .background(Color.black)
}
#endif
