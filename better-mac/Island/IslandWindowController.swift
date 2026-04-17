import AppKit
import SwiftUI
import Combine

/// Hosts the NSPanel that renders the Dynamic Island. Owns frame animation
/// between the collapsed (notch) and expanded rects.
@MainActor
final class IslandWindowController: NSObject {
    // Tuneable geometry
    // Expansion is vertical-only: width and x match the hardware notch so
    // the panel drops straight down from it. Only height is a free parameter.
    private let expandedHeight: CGFloat = 180
    // Additional height over the collapsed rect during the peek state.
    // Small enough to read as a hover hint, big enough to not look like jitter.
    private let peekHeightDelta: CGFloat = 12
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
    private var hoverLevel: HoverLevel = .none

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
        self.hotZone = IslandHotZone { [weak self] newLevel in
            Task { @MainActor in
                self?.setHoverLevel(newLevel)
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

    /// Resolve the target panel frame for a given island state. All four
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
        case .peek:
            return peekRect(from: collapsed)
        case .expanded:
            return expandedRect(from: collapsed)
        }
    }

    private func collapsedRect() -> CGRect {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        return screen.islandCollapsedRect
    }

    private func expandedRect(from collapsed: CGRect) -> CGRect {
        // Vertical-only expansion: width matches whatever the pre-expansion
        // state was showing — the notch width when idle, the playing pill's
        // width when a track is loaded. Centered on the same axis as the
        // notch (screen midX). Top stays flush with the screen edge to avoid
        // both a visual gap and the hover-flicker it used to cause.
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let width = store.hasTrack ? playingWidth : collapsed.width
        let x = screen.frame.midX - width / 2
        let y = collapsed.maxY - expandedHeight
        return CGRect(x: x, y: y, width: width, height: expandedHeight)
    }

    private func peekRect(from collapsed: CGRect) -> CGRect {
        // Same width rule as expanded — vertical-only grow by `peekHeightDelta`
        // over the collapsed height. Top stays flush with the screen edge.
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let width = store.hasTrack ? playingWidth : collapsed.width
        let x = screen.frame.midX - width / 2
        let height = collapsed.height + peekHeightDelta
        let y = collapsed.maxY - height
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

    /// Called from the hot zone callback. Records the new hover level and
    /// triggers a full resolve.
    private func setHoverLevel(_ newLevel: HoverLevel) {
        guard hoverLevel != newLevel else { return }
        hoverLevel = newLevel
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
                    guard let self else { return }
                    self.updateResolvedState()
                    // While peeking or expanded the resolved state stays the
                    // same across a hasTrack flip, so the container observer's
                    // removeDuplicates suppresses the frame animation. Both
                    // rect widths depend on hasTrack, so re-animate explicitly.
                    let current = self.container.state
                    if current == .expanded || current == .peek {
                        self.animateFrame(for: current)
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Re-resolve the island state from the current inputs and push the
    /// result into the observable container. Transitions are animated by
    /// `observeContainerState()` further down.
    private func updateResolvedState() {
        container.state = IslandStateResolver.resolve(
            hover: hoverLevel,
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
        let isCollapsing = (state == .idle || state == .playing)

        NSAnimationContext.runAnimationGroup { ctx in
            // Asymmetric timing: open is slower with a smooth ease-out tail
            // so peek/expand feels gentle and intentional; close is snappier
            // so dismissal feels responsive. `display: false` skips the
            // synchronous redraw per tick — the compositor schedules its own.
            if isCollapsing {
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            } else {
                ctx.duration = 0.30
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0)
            }
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
