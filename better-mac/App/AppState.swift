import Foundation
import SwiftUI
import Combine

/// Central observable settings container. Mirrors `@AppStorage` keys so SwiftUI
/// and AppKit menu items can drive the same underlying `UserDefaults`.
@MainActor
final class AppState: ObservableObject {
    static let islandEnabledKey = "islandEnabled"
    static let volumeHUDEnabledKey = "volumeHUDEnabled"
    static let openAtLoginKey = "openAtLogin"
    static let showVolumePercentageKey = "showVolumePercentage"

    @Published var islandEnabled: Bool {
        didSet { UserDefaults.standard.set(islandEnabled, forKey: Self.islandEnabledKey) }
    }
    @Published var volumeHUDEnabled: Bool {
        didSet { UserDefaults.standard.set(volumeHUDEnabled, forKey: Self.volumeHUDEnabledKey) }
    }
    @Published var openAtLogin: Bool {
        didSet { UserDefaults.standard.set(openAtLogin, forKey: Self.openAtLoginKey) }
    }
    @Published var showVolumePercentage: Bool {
        didSet { UserDefaults.standard.set(showVolumePercentage, forKey: Self.showVolumePercentageKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        // Register defaults (first-launch values). Open-at-login defaults
        // to true so a fresh install of the notarized .dmg auto-registers
        // with SMAppService and relaunches on every reboot. Users can still
        // opt out from the menu bar toggle.
        defaults.register(defaults: [
            Self.islandEnabledKey: true,
            Self.volumeHUDEnabledKey: true,
            Self.openAtLoginKey: true,
            Self.showVolumePercentageKey: false
        ])
        self.islandEnabled = defaults.bool(forKey: Self.islandEnabledKey)
        self.volumeHUDEnabled = defaults.bool(forKey: Self.volumeHUDEnabledKey)
        self.openAtLogin = defaults.bool(forKey: Self.openAtLoginKey)
        self.showVolumePercentage = defaults.bool(forKey: Self.showVolumePercentageKey)
    }
}
