import AppKit
import Combine
import ServiceManagement

/// AppDelegate is the long-lived owner of every subsystem (island, volume HUD,
/// media bridge, audio monitor, interceptor). Using a single owner on the main
/// actor prevents lifetime bugs where NSPanels and CFRunLoop sources get
/// deallocated out from under the system.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()

    // Subsystems (lazily created once the launch finishes).
    private var statusItem: NSStatusItem?
    private var islandController: IslandWindowController?
    private var volumeHUDController: VolumeHUDWindowController?
    private var audioMonitor: AudioOutputMonitor?
    private var volumeInterceptor: VolumeKeyInterceptor?
    private var mediaRemote: MediaRemoteBridge?
    private var nowPlaying: NowPlayingStore?

    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // We are LSUIElement=YES via Info.plist. Enforce activation policy for
        // belt-and-suspenders safety in case of misconfiguration.
        NSApp.setActivationPolicy(.accessory)

        Log.app.info("better-mac launching")

        installStatusItem()
        installSubsystems()
        observeSettings()
        observeWorkspace()

        // Kick a first-launch accessibility nudge for the volume feature.
        if appState.volumeHUDEnabled, !Permissions.isAccessibilityTrusted() {
            Permissions.promptAccessibilityIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("better-mac terminating")
        volumeInterceptor?.stop()
    }

    // MARK: - Status bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "waveform.badge.mic",
            accessibilityDescription: "better-mac"
        )
        item.button?.image?.isTemplate = true

        let menu = NSMenu()

        let islandItem = NSMenuItem(
            title: "Enable Dynamic Island",
            action: #selector(toggleIsland),
            keyEquivalent: ""
        )
        islandItem.target = self
        islandItem.state = appState.islandEnabled ? .on : .off
        menu.addItem(islandItem)

        let volumeItem = NSMenuItem(
            title: "Enable Volume HUD",
            action: #selector(toggleVolumeHUD),
            keyEquivalent: ""
        )
        volumeItem.target = self
        volumeItem.state = appState.volumeHUDEnabled ? .on : .off
        menu.addItem(volumeItem)

        let loginItem = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleOpenAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = appState.openAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit better-mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        self.statusItem = item
    }

    private func refreshStatusItemState() {
        guard let menu = statusItem?.menu else { return }
        menu.item(withTitle: "Enable Dynamic Island")?.state = appState.islandEnabled ? .on : .off
        menu.item(withTitle: "Enable Volume HUD")?.state = appState.volumeHUDEnabled ? .on : .off
        menu.item(withTitle: "Open at Login")?.state = appState.openAtLogin ? .on : .off
    }

    // MARK: - Subsystem wiring

    private func installSubsystems() {
        // Media
        let bridge = MediaRemoteBridge()
        let spotify = SpotifyAppleScriptClient()
        let store = NowPlayingStore(bridge: bridge, spotify: spotify)
        self.mediaRemote = bridge
        self.nowPlaying = store
        bridge.start()
        store.start()

        // Audio monitor + HUD
        let audio = AudioOutputMonitor()
        audio.start()
        self.audioMonitor = audio

        let hud = VolumeHUDWindowController(appState: appState, audio: audio)
        self.volumeHUDController = hud

        // Key interceptor
        let interceptor = VolumeKeyInterceptor(audio: audio) { [weak hud, weak audio] in
            guard let hud, let audio else { return }
            hud.show(volume: audio.currentVolume, muted: audio.isMuted, kind: audio.current.kind, deviceName: audio.current.displayName)
        }
        self.volumeInterceptor = interceptor
        if appState.volumeHUDEnabled {
            interceptor.start()
        }

        // Island
        let island = IslandWindowController(store: store, appState: appState)
        self.islandController = island
        if appState.islandEnabled {
            island.show()
        }
    }

    private func observeSettings() {
        appState.$islandEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.islandController?.show() } else { self.islandController?.hide() }
                self.refreshStatusItemState()
            }
            .store(in: &cancellables)

        appState.$volumeHUDEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    if !Permissions.isAccessibilityTrusted() {
                        Permissions.promptAccessibilityIfNeeded()
                    }
                    self.volumeInterceptor?.start()
                } else {
                    self.volumeInterceptor?.stop()
                }
                self.refreshStatusItemState()
            }
            .store(in: &cancellables)

        appState.$openAtLogin
            .removeDuplicates()
            .sink { [weak self] enabled in
                Self.applyOpenAtLogin(enabled)
                self?.refreshStatusItemState()
            }
            .store(in: &cancellables)
    }

    private func observeWorkspace() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.islandController?.reposition()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // CGEventTap can get disabled on sleep. Self-heal on wake.
                self?.volumeInterceptor?.reenable()
            }
        }
    }

    // MARK: - Menu actions

    @objc private func toggleIsland() {
        appState.islandEnabled.toggle()
    }

    @objc private func toggleVolumeHUD() {
        appState.volumeHUDEnabled.toggle()
    }

    @objc private func toggleOpenAtLogin() {
        appState.openAtLogin.toggle()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Open at Login

    private static func applyOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            Log.app.error("Open-at-Login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
