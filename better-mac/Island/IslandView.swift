import AppKit
import SwiftUI

/// Visual states for the island content. The panel's frame is driven by the
/// controller; `IslandView` only renders content that matches the current
/// state.
///
/// - `idle`: no active media — plain black notch.
/// - `playing`: a track is loaded — black pill with artwork + waveform.
/// - `peek`: cursor has just entered the hot zone — a subtle height hint
///   shown before the dwell timer promotes to `.expanded`.
/// - `expanded`: cursor has dwelled in the hot zone — full media UI.
enum IslandState: Equatable {
    case idle
    case playing
    case peek
    case expanded
}

struct IslandView: View {
    let state: IslandState
    @ObservedObject var store: NowPlayingStore

    // Corner radius at the bottom matches the physical notch's rounded edge
    // for a seamless extension illusion on notched MacBooks. The playing
    // state shares the notch radius so the widened pill reads as a horizontal
    // extension of the hardware notch, not a distinct capsule.
    private let notchCorner: CGFloat = 10
    private let playingCorner: CGFloat = 10
    private let expandedCorner: CGFloat = 22

    // Top margin reserved for the hardware notch cutout. Read off the active
    // screen so content sits just below the camera island; fall back to 32pt
    // on non-notched Macs to match the pill fallback height.
    static var notchTopInset: CGFloat {
        (NSScreen.main?.safeAreaInsets.top).flatMap { $0 > 0 ? $0 : nil } ?? 32
    }

    var body: some View {
        ZStack {
            background
            switch state {
            case .idle:
                EmptyView()
            case .playing:
                PlayingCollapsedContent(store: store)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .transition(.opacity)
            case .peek:
                // Pure hover hint: no inner content. The taller black pill
                // is the signal.
                EmptyView()
            case .expanded:
                ExpandedIslandContent(store: store)
                    .padding(.horizontal, 10)
                    // Reserve the collapsed notch's height at the top so
                    // nothing renders behind the hardware camera cutout.
                    .padding(.top, Self.notchTopInset)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        // Match the window controller's open-path frame animation so the
        // content crossfade lands in lock-step with the panel resize. Plain
        // opacity only (no scale) keeps the GPU path simple.
        .animation(.easeOut(duration: 0.30), value: state)
    }

    @ViewBuilder
    private var background: some View {
        switch state {
        case .idle:
            // Rounded only on the bottom so the top aligns with the menu bar
            // and extends the notch shape downward.
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: notchCorner,
                    bottomTrailing: notchCorner,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .fill(Color.black)
        case .playing:
            // Pill: top-flush with the menu bar, heavier bottom corners so it
            // reads as distinct from the expanded panel (22) and the idle
            // notch extension (10).
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: playingCorner,
                    bottomTrailing: playingCorner,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .fill(Color.black)
        case .peek:
            // Bottom-rounded like idle/playing. Top corners round to
            // `notchCorner` only when the peek is wider than the hardware
            // notch (hasTrack → playingWidth) so the corners that poke out
            // into the menu bar area look intentional. At notch width the
            // corners sit under the camera cutout and the radius is invisible.
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: store.hasTrack ? notchCorner : 0,
                    bottomLeading: playingCorner,
                    bottomTrailing: playingCorner,
                    topTrailing: store.hasTrack ? notchCorner : 0
                ),
                style: .continuous
            )
            .fill(Color.black)
        case .expanded:
            // Top corners match the notch-corner radius: when expanded from
            // the playing pill the panel extends past the notch horizontally,
            // so the top edges are visible in the menu bar area and need
            // rounding. When expanded from idle (notch width) the corners
            // fall under the camera cutout and the radius is invisible.
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: notchCorner,
                    bottomLeading: expandedCorner,
                    bottomTrailing: expandedCorner,
                    topTrailing: notchCorner
                ),
                style: .continuous
            )
            .fill(Color.black)
        }
    }
}

private struct ExpandedIslandContent: View {
    @ObservedObject var store: NowPlayingStore

    var body: some View {
        if store.hasTrack {
            VStack(spacing: 8) {
                ArtworkView(image: store.artworkImage)
                    .frame(width: 52, height: 52)

                VStack(spacing: 2) {
                    Text(store.title ?? "Unknown")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(store.artist ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                IslandControlsView(store: store)

                SeekBarView(
                    elapsed: store.elapsed,
                    duration: store.duration,
                    onSeek: { seconds in
                        store.seek(to: seconds)
                    }
                )
                .frame(height: 14)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.7))
                Text("Nothing Playing")
                    .foregroundStyle(.white.opacity(0.8))
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PlayingCollapsedContent: View {
    @ObservedObject var store: NowPlayingStore

    var body: some View {
        // Size content off the container's actual height (the pill is now
        // the same height as the notch, which varies by Mac model). The
        // thumbnail fills the vertical slot minus small margins; the
        // volumizer sits to the right.
        GeometryReader { proxy in
            let slot = proxy.size.height
            let thumb = max(0, slot - 6)
            HStack(spacing: 8) {
                ArtworkView(image: store.artworkImage)
                    .frame(width: thumb, height: thumb)

                Spacer(minLength: 0)

                VolumizerView(isAnimating: store.isPlaying)
                    .frame(width: thumb, height: max(0, thumb - 8))
                    .padding(.trailing, 2)
            }
        }
    }
}

private struct ArtworkView: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.7))
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
