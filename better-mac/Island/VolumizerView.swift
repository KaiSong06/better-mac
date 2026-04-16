import SwiftUI

/// iPhone Dynamic Island-style audio activity indicator: a small row of
/// vertical capsule bars that bounce at staggered rates while audio plays
/// and freeze at a low rest height when paused.
///
/// Not driven by real audio — it's a stylised animation. Apple uses the
/// same trick on iOS.
struct VolumizerView: View {
    var isAnimating: Bool = true
    var color: Color = .white
    var barCount: Int = 4
    var spacing: CGFloat = 3
    var barWidth: CGFloat = 3
    /// Resting height as a fraction of the slot when paused, and the floor
    /// the bars never go below while animating.
    var minHeightFraction: CGFloat = 0.25
    var maxHeightFraction: CGFloat = 1.0

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation) { context in
                    bars(at: context.date)
                }
            } else {
                bars(at: nil)
            }
        }
    }

    @ViewBuilder
    private func bars(at date: Date?) -> some View {
        GeometryReader { proxy in
            let slotHeight = proxy.size.height
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: barHeight(for: index, slotHeight: slotHeight, date: date))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: slotHeight, alignment: .bottom)
        }
    }

    /// Compute a per-bar height. Each bar gets its own (frequency, phase)
    /// pair so the row never visually syncs.
    private func barHeight(for index: Int, slotHeight: CGFloat, date: Date?) -> CGFloat {
        let minH = slotHeight * minHeightFraction
        let maxH = slotHeight * maxHeightFraction

        guard let date else {
            // Frozen: every bar at the same low rest height.
            return minH
        }

        // Hand-tuned to feel "alive" without being chaotic.
        let frequencies: [Double] = [3.7, 5.1, 4.2, 6.3]
        let phases: [Double]      = [0.0, 1.1, 2.3, 3.4]

        let f = frequencies[index % frequencies.count]
        let p = phases[index % phases.count]

        let t = date.timeIntervalSinceReferenceDate
        // Map sin(...) ∈ [-1, 1] → [0, 1] then scale into the [minH, maxH] band.
        let unit = (sin(2 * .pi * f * t * 0.18 + p) + 1) / 2
        return minH + CGFloat(unit) * (maxH - minH)
    }
}

#if DEBUG
#Preview("Animating") {
    VolumizerView()
        .frame(width: 32, height: 20)
        .padding()
        .background(Color.black)
}

#Preview("Frozen") {
    VolumizerView(isAnimating: false)
        .frame(width: 32, height: 20)
        .padding()
        .background(Color.black)
}
#endif
