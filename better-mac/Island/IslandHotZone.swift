import AppKit

/// Tracks mouse position and drives peek/expand/collapse of the island.
///
/// - Installs an `NSTrackingArea` on the panel's content view for precise
///   enter/exit while the cursor is inside the panel bounds.
/// - Falls back on a global mouse monitor while hovering so we can detect the
///   cursor crossing the outer edge of the hot zone (tracking areas don't
///   report events outside the panel frame).
/// - On entry, sets `level = .peek` immediately and starts a dwell timer.
///   If the cursor stays in the hot zone for `peekDwell` seconds, the level
///   promotes to `.full`. Otherwise a debounced collapse returns to `.none`.
@MainActor
final class IslandHotZone: NSObject {
    private(set) var level: HoverLevel = .none {
        didSet {
            if oldValue != level { onChange(level) }
        }
    }

    private weak var contentView: NSView?
    private var trackingArea: NSTrackingArea?
    private var globalMonitor: Any?
    private let onChange: (HoverLevel) -> Void

    /// Short hysteresis on collapse. Long enough to absorb enter/exit jitter
    /// at the tracking-area boundary, short enough to feel instant.
    private let collapseDebounce: TimeInterval = 0.06
    private var collapseWork: DispatchWorkItem?

    /// Dwell required before peek promotes to full expansion. Injectable so
    /// tests can shorten it.
    private let peekDwell: TimeInterval
    private var peekDwellWork: DispatchWorkItem?

    init(peekDwell: TimeInterval = 0.75, onChange: @escaping (HoverLevel) -> Void) {
        self.peekDwell = peekDwell
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

    @objc func mouseEntered(_ event: NSEvent) {
        enter()
    }

    @objc func mouseExited(_ event: NSEvent) {
        exit()
    }

    // MARK: - Public API (also used by hosting NSView's events)

    func enter() {
        // Any fresh entry cancels a pending collapse — this is how the
        // hysteresis absorbs jitter at the tracking-area boundary.
        collapseWork?.cancel()
        collapseWork = nil

        // Only transition on `.none → .peek`. Repeat `enter()` calls while
        // already peeking or fully expanded must NOT reset the dwell timer —
        // mouseMoved jitter inside the hot zone would otherwise keep the
        // panel stuck at peek forever.
        switch level {
        case .none:
            level = .peek
            startGlobalMonitor()
            schedulePeekDwell()
        case .peek, .full:
            break
        }
    }

    func exit() {
        // Still inside the logical hot zone (union of panel frame and the
        // physical notch)? Not a real exit.
        if cursorInsideHotZone() { return }

        // Kill the pending dwell too — otherwise a fired-after-exit dwell
        // could promote us back to full while the user's already gone.
        peekDwellWork?.cancel()
        peekDwellWork = nil

        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.cursorInsideHotZone() { return }
            if self.level != .none {
                self.level = .none
                self.stopGlobalMonitor()
            }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDebounce, execute: work)
    }

    private func schedulePeekDwell() {
        peekDwellWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Re-check at fire time: the cursor may have left during the
            // dwell window (in which case exit() already scheduled collapse
            // and we should not contradict it).
            guard self.cursorInsideHotZone() else { return }
            if self.level == .peek { self.level = .full }
        }
        peekDwellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + peekDwell, execute: work)
    }

    /// True iff the cursor is inside the union of the current panel frame
    /// and the physical notch rect. The notch rect is always included so
    /// that cursor positions at the very top edge of the screen (above the
    /// expanded panel's top) don't count as exits.
    private func cursorInsideHotZone() -> Bool {
        guard let window = contentView?.window else { return false }
        let p = NSEvent.mouseLocation
        let notchFrame = (window.screen ?? NSScreen.main)?.islandCollapsedRect ?? .zero
        let combined = window.frame.union(notchFrame)
        return combined.contains(p)
    }

    // MARK: - Global monitor for leaving the hot zone

    private func startGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self else { return }
            if !self.cursorInsideHotZone() {
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
