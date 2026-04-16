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

    private let hudSize = CGSize(width: 64, height: 220)
    private let edgeInset: CGFloat = 16
    private var dismissWork: DispatchWorkItem?
    private let dismissAfter: TimeInterval = 1.8

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
    }

    func show(volume: Float, muted: Bool, kind: OutputKind, deviceName: String) {
        model.update(volume: volume, muted: muted, kind: kind, deviceName: deviceName)

        reposition()
        panel.orderFrontRegardless()
        // Re-assert no-shadow after order-front; macOS sometimes restores
        // the default panel shadow on activation.
        panel.hasShadow = false
        panel.invalidateShadow()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    private func reposition() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame = screen.visibleFrame
        let x = frame.maxX - hudSize.width - edgeInset
        let y = frame.midY - hudSize.height / 2
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
