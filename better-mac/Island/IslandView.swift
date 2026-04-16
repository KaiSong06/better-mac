import SwiftUI

/// Visual states for the island content. The panel's frame is driven by the
/// controller; `IslandView` only renders content that matches the current
/// state.
///
/// - `idle`: no active media — plain black notch.
/// - `playing`: a track is loaded — black pill with artwork + waveform.
/// - `expanded`: cursor is hovering — full media UI.
enum IslandState: Equatable {
    case idle
    case playing
    case expanded
}

struct IslandView: View {
    let state: IslandState
    @ObservedObject var store: NowPlayingStore

    // Corner radius at the bottom matches the physical notch's rounded edge
    // for a seamless extension illusion on notched MacBooks.
    private let notchCorner: CGFloat = 10
    private let expandedCorner: CGFloat = 22

    var body: some View {
        ZStack {
            background
            if state == .expanded {
                ExpandedIslandContent(store: store)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.22), value: state)
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
            // Placeholder in Unit 1 — same shape as .idle, filled black.
            // Unit 4 replaces this with a wider compact layout.
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
        case .expanded:
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
                HStack(spacing: 12) {
                    ArtworkView(image: store.artworkImage)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.title ?? "Unknown")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(store.artist ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)

                    AppSourceIcon(bundleID: store.sourceBundleID)
                        .frame(width: 16, height: 16)
                }

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
            HStack {
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.7))
                Text("Nothing Playing")
                    .foregroundStyle(.white.opacity(0.8))
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.vertical, 18)
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
