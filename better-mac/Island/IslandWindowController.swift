import AppKit
import SwiftUI
import Combine

/// Hosts the NSPanel that renders the Dynamic Island. Owns frame animation
/// between the collapsed (notch) and expanded rects.
@MainActor
final class IslandWindowController: NSObject {
    // Tuneable geometry
    private let expandedSize = CGSize(width: 420, height: 140)
    private let expandedTopPadding: CGFloat = 4  // visible distance below the menu bar
    private let collapsedHoverPadX: CGFloat = 8
    private let collapsedHoverPadY: CGFloat = 6

    private let panel: IslandPanel
    private let hostingView: NSHostingView<IslandContainer>
    private let container: ObservableContainer
    private let hotZone: IslandHotZone
    private let store: NowPlayingStore
    private let appState: AppState
    private var cancellables: Set<AnyCancellable> = []
    private var isShown = false

    init(store: NowPlayingStore, appState: AppState) {
        self.store = store
        self.appState = appState

        self.container = ObservableContainer(state: .idle)
        self.hostingView = NSHostingView(rootView: IslandContainer(container: container, store: store))
        self.hostingView.translatesAutoresizingMaskIntoConstraints = false

        let panel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        // Sits above the menu bar and most overlays while still cooperating
        // with fullscreen apps (fullScreenAuxiliary in collectionBehavior).
        panel.level = NSWindow.Level.mainMenu + 3
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.ignoresMouseEvents = false
        panel.contentView = hostingView
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: content.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
        }
        self.panel = panel

        let weakContainer = container
        self.hotZone = IslandHotZone { [weak weakContainer] newState in
            Task { @MainActor in
                // Unit 3 will replace this direct mapping with
                // IslandStateResolver.resolve(hovering:hasTrack:) so track
                // state participates in the decision. For now a hover-out
                // always parks us in .idle.
                weakContainer?.state = (newState == .expanded) ? .expanded : .idle
            }
        }

        super.init()

        hotZone.attach(to: hostingView)
        observeContainerState()

        // Reposition if displays change.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
    }

    @objc func onScreenChange() {
        reposition()
    }

    func reposition() {
        panel.setFrame(frame(for: container.state), display: true, animate: false)
        hotZone.refreshTrackingArea()
    }

    // MARK: - Frame math

    /// Resolve the target panel frame for a given island state. All three
    /// states center on the main screen's notch.
    private func frame(for state: IslandState) -> CGRect {
        let collapsed = collapsedRect()
        switch state {
        case .idle:
            return collapsed
        case .playing:
            // Placeholder geometry in Unit 1 — identical to .idle. Unit 3
            // replaces this with the wider playing pill.
            return collapsed
        case .expanded:
            return expandedRect(from: collapsed)
        }
    }

    private func collapsedRect() -> CGRect {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        return screen.islandCollapsedRect
    }

    private func expandedRect(from collapsed: CGRect) -> CGRect {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let top = screen.frame.maxY
        let width = expandedSize.width
        let height = expandedSize.height
        let x = screen.frame.midX - width / 2
        // The expanded rect sits flush under the menu bar so the visual top
        // aligns with the notch opening.
        let y = top - height - expandedTopPadding
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - State observation

    private func observeContainerState() {
        container.$state
            .removeDuplicates()
            .sink { [weak self] newState in
                self?.animateFrame(for: newState)
            }
            .store(in: &cancellables)
    }

    private func animateFrame(for state: IslandState) {
        let target = frame(for: state)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.hotZone.refreshTrackingArea()
            }
        }
    }
}

// MARK: - Supporting types

/// `NSPanel` subclass that accepts first responder status even though the
/// panel is borderless/nonactivating. Lets SwiftUI buttons inside receive
/// clicks without forcing the app to activate.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Small observable bridge so SwiftUI's animation tracks container.state
/// while the hot zone (AppKit) can also push state changes into SwiftUI.
@MainActor
final class ObservableContainer: ObservableObject {
    @Published var state: IslandState
    init(state: IslandState) { self.state = state }
}

/// Top-level SwiftUI container for the island panel.
struct IslandContainer: View {
    @ObservedObject var container: ObservableContainer
    @ObservedObject var store: NowPlayingStore

    var body: some View {
        IslandView(state: container.state, store: store)
    }
}
