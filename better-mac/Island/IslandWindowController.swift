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
    // Playing-state width only; the height matches the idle notch so the
    // pill reads as a horizontally-extended version of the same shape.
    private let playingWidth: CGFloat = 260

    private let panel: IslandPanel
    private let hostingView: NSHostingView<IslandContainer>
    private let container: ObservableContainer
    private var hotZone: IslandHotZone!
    private let store: NowPlayingStore
    private let appState: AppState
    private var cancellables: Set<AnyCancellable> = []
    private var isShown = false

    /// Latest raw inputs. Both feed into `IslandStateResolver.resolve` via
    /// `updateResolvedState()`.
    private var isHovering = false

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

        super.init()

        // After super.init we can capture self for the hot zone callback.
        self.hotZone = IslandHotZone { [weak self] newState in
            Task { @MainActor in
                self?.setHovering(newState == .expanded)
            }
        }
        hotZone.attach(to: hostingView)

        observeContainerState()
        observeStore()

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
            let screen = NSScreen.main ?? NSScreen.screens.first!
            // Use the notch's own height for the pill so the widened shape
            // is a flush continuation of the hardware notch — no vertical
            // seam when the island transitions between idle and playing.
            let size = CGSize(width: playingWidth, height: collapsed.height)
            return Self.playingRect(in: screen.frame, size: size)
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

    /// Pure rect math: position the playing pill flush to the top-center of
    /// the given screen. Exposed as `nonisolated static` for unit testing.
    nonisolated static func playingRect(in screenFrame: CGRect, size: CGSize) -> CGRect {
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height  // top-flush
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Input wiring

    /// Called from the hot zone callback. Records the new hover state and
    /// triggers a full resolve.
    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        updateResolvedState()
    }

    /// Subscribe to whatever NowPlayingStore publishes that can change
    /// `hasTrack`. `title` is the canonical signal: `hasTrack` is a title-
    /// presence check, so any change there can flip the answer.
    private func observeStore() {
        store.$title
            .map { $0?.isEmpty == false }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateResolvedState()
                }
            }
            .store(in: &cancellables)
    }

    /// Re-resolve the island state from the current inputs and push the
    /// result into the observable container. Transitions are animated by
    /// `observeContainerState()` further down.
    private func updateResolvedState() {
        container.state = IslandStateResolver.resolve(
            hovering: isHovering,
            hasTrack: store.hasTrack
        )
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
            // Tight duration + a snappy custom cubic (fast lead-in, smooth
            // settle) so the expand feels immediate instead of easing slowly
            // out from rest. `display: false` skips the synchronous redraw
            // each animation tick — the window compositor schedules its own.
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: false)
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
