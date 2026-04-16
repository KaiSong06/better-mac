import SwiftUI

struct IslandControlsView: View {
    @ObservedObject var store: NowPlayingStore

    var body: some View {
        HStack(spacing: 18) {
            Spacer()
            controlButton(symbol: "backward.fill") { store.previous() }
            controlButton(
                symbol: store.isPlaying ? "pause.fill" : "play.fill",
                size: 18
            ) { store.toggle() }
            controlButton(symbol: "forward.fill") { store.next() }
            Spacer()
        }
    }

    private func controlButton(symbol: String, size: CGFloat = 14, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentShape(Rectangle())
                .frame(minWidth: 22, minHeight: 22)
        }
        .buttonStyle(.plain)
    }
}
