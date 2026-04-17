import AppKit
import Combine
import SwiftUI

@MainActor
final class VolumeHUDWindowController {
    private let appState: AppState
    private let audio: AudioOutputMonitor

    private let panel: NSPanel
    private let hostingView: NSHostingView<ContentWrapper>
    private let model: HUDModel

    // Host panel size.
    //  - Width: pill + left shadow margin + right-edge inset. The pill is
    //    trailing-aligned with `edgeInsetFromScreen` of trailing padding
    //    (see VolumeHUDView), so the right side of the panel holds the
    //    screen-edge gap that the padding creates. That same gap also
    //    gives the drop shadow on the right bleed room.
    //  - Height: pill + vertical shadow margins on top and bottom.
    private var hudSize: CGSize {
        CGSize(
            width: VolumeHUDView.pillSize.width + VolumeHUDView.shadowMarginH + VolumeHUDView.edgeInsetFromScreen,
            height: VolumeHUDView.pillSize.height + VolumeHUDView.shadowMarginV * 2
        )
    }
    private var dismissWork: DispatchWorkItem?
    // iOS auto-dismisses the volume HUD ~1.5 s after the last adjustment.
    private let dismissAfter: TimeInterval = 1.5
    // True while a fadeOut animation is in flight. A concurrent show()
    // clears this so the fadeOut's completion handler does not call
    // orderOut on the panel the show() just raised.
    private var isDismissing = false

    init(appState: AppState, audio: AudioOutputMonitor) {
        self.appState = appState
        self.audio = audio
        self.model = HUDModel()

        let panel = NSPanel(
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
        // .floating sits above normal windows but doesn't carry the implicit
        // system shadow that .screenSaver / popUpMenu levels do on Tahoe.
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0

        let hosting = NSHostingView(rootView: ContentWrapper(model: model, appState: appState))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Belt-and-suspenders: explicitly clear the hosting view's layer so
        // the capsule isn't framed by an implicit grey rectangle on macOS
        // versions that give NSHostingView a default backgroundColor.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: content.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
        }

        self.panel = panel
        self.hostingView = hosting

        reposition()

        // Reposition on screen changes — external display hot-plug, resolution
        // change, menu-bar visibility toggles. Mirrors IslandWindowController.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func onScreenChange() {
        reposition()
    }

    func show(volume: Float, muted: Bool, kind: OutputKind, deviceName: String) {
        model.update(volume: volume, muted: muted, kind: kind, deviceName: deviceName)

        // A show() during a fadeOut must cancel the fadeOut's deferred
        // orderOut — otherwise the old completion handler fires after the
        // new alpha→1 animation and snap-hides the panel the user is
        // looking at.
        isDismissing = false

        reposition()
        panel.orderFrontRegardless()
        // Re-assert no-shadow after order-front; macOS sometimes restores
        // the default panel shadow on activation.
        panel.hasShadow = false
        panel.invalidateShadow()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter, execute: work)
    }

    private func fadeOut() {
        isDismissing = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.isDismissing else { return }
            self.isDismissing = false
            self.panel.orderOut(nil)
        }
    }

    private func reposition() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        // Hybrid placement:
        //  - X: use visibleFrame.maxX so the pill respects a Dock on the
        //    right (sits adjacent to it, not underneath). On Dock-bottom /
        //    Dock-left / Dock-auto-hide setups visibleFrame.maxX equals
        //    frame.maxX, so the pill is flush with the physical screen edge.
        //  - Y: use frame.midY so the HUD's vertical position is stable
        //    regardless of Dock auto-hide state.
        let x = screen.visibleFrame.maxX - hudSize.width
        let y = screen.frame.midY - hudSize.height / 2
        panel.setFrame(CGRect(x: x, y: y, width: hudSize.width, height: hudSize.height), display: true, animate: false)
    }
}

/// Tiny observable backing the HUD so we can mutate state from the controller
/// and SwiftUI sees the change without re-creating the view tree.
@MainActor
final class HUDModel: ObservableObject {
    @Published var volume: Float = 0
    @Published var muted: Bool = false
    @Published var kind: OutputKind = .builtInSpeakers
    @Published var deviceName: String = "Speakers"

    func update(volume: Float, muted: Bool, kind: OutputKind, deviceName: String) {
        // Plain assignment — no withAnimation. The fill Rectangle and the
        // inversion mask in VolumeHUDView each carry an explicit
        // `.animation(VolumeHUDView.volumeSpring, value: fillH)` modifier,
        // so the spring lives at exactly one place per layer. Wrapping an
        // ambient withAnimation here would create a competing transaction
        // that drives the mask Rectangle while the fill Rectangle's
        // view-local modifier drives its own copy, producing a ~1-frame
        // divergence at the inversion boundary under load.
        self.volume = volume
        self.muted = muted
        self.kind = kind
        self.deviceName = deviceName
    }
}

struct ContentWrapper: View {
    @ObservedObject var model: HUDModel
    @ObservedObject var appState: AppState

    var body: some View {
        VolumeHUDView(
            volume: model.volume,
            muted: model.muted,
            kind: model.kind,
            deviceName: model.deviceName,
            showPercentage: appState.showVolumePercentage
        )
    }
}
