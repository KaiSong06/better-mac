import AppKit

/// Tracks mouse position and drives expand/collapse of the island.
///
/// - Installs an `NSTrackingArea` on the panel's content view for precise
///   enter/exit while the cursor is inside the expanded panel bounds.
/// - Falls back on a global mouse monitor while expanded so we can detect the
///   cursor crossing the outer edge of the expanded region (tracking areas
///   don't report events outside the panel frame).
@MainActor
final class IslandHotZone: NSObject {
    enum State: Equatable { case collapsed, expanded }

    private(set) var state: State = .collapsed {
        didSet {
            if oldValue != state { onChange(state) }
        }
    }

    private weak var contentView: NSView?
    private var trackingArea: NSTrackingArea?
    private var globalMonitor: Any?
    private let onChange: (State) -> Void

    /// Short hysteresis on collapse. Long enough to absorb enter/exit jitter
    /// at the tracking-area boundary (the source of the flicker you'd see
    /// with a zero-grace collapse), short enough to feel instant to a human.
    /// A fresh `enter()` cancels the pending collapse.
    private let collapseDebounce: TimeInterval = 0.06
    private var collapseWork: DispatchWorkItem?

    init(onChange: @escaping (State) -> Void) {
        self.onChange = onChange
        super.init()
    }

    // MARK: - Attachment

    func attach(to view: NSView) {
        self.contentView = view
        installTrackingArea()
    }

    /// Re-install the tracking area after the panel frame changes. Needed
    /// because tracking areas are pinned to the view's bounds at creation.
    func refreshTrackingArea() {
        installTrackingArea()
    }

    private func installTrackingArea() {
        guard let view = contentView else { return }
        if let existing = trackingArea {
            view.removeTrackingArea(existing)
            trackingArea = nil
        }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Callbacks from the tracking area
    // NSTrackingArea sends mouseEntered:/mouseExited: to its owner using the
    // standard NSResponder selectors even when the owner is a plain NSObject.

    @objc func mouseEntered(_ event: NSEvent) {
        enter()
    }

    @objc func mouseExited(_ event: NSEvent) {
        exit()
    }

    // MARK: - Public API (also used by hosting NSView's events)

    func enter() {
        // A pending collapse is cancelled by any fresh enter — this is how
        // the anti-flicker hysteresis collapses back to stable on jitter.
        collapseWork?.cancel()
        collapseWork = nil
        if state != .expanded {
            state = .expanded
            startGlobalMonitor()
        }
    }

    func exit() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.state != .collapsed {
                self.state = .collapsed
                self.stopGlobalMonitor()
            }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDebounce, execute: work)
    }

    // MARK: - Global monitor for leaving the expanded bounds

    private func startGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self, let window = self.contentView?.window else { return }
            let p = NSEvent.mouseLocation
            if !window.frame.contains(p) {
                self.exit()
            }
        }
    }

    private func stopGlobalMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
}
