import Foundation
import Sparkle

/// Thin wrapper around Sparkle so the rest of the app sees a small surface:
/// one shared updater plus an API that maps to the delegate-less Sparkle v2
/// lifecycle.
///
/// Sparkle reads its configuration from Info.plist:
///   - SUFeedURL         — URL of the appcast XML
///   - SUPublicEDKey     — EdDSA public key used to verify updates
///   - SUEnableAutomaticChecks / SUScheduledCheckInterval
///
/// The release script (scripts/release.sh) injects the real SUPublicEDKey at
/// build time via Info.plist overrides — the value checked into git is a
/// placeholder.
@MainActor
final class UpdaterController: NSObject {
    static let shared = UpdaterController()

    let controller: SPUStandardUpdaterController

    var updater: SPUUpdater { controller.updater }

    override init() {
        // startingUpdater: true means Sparkle begins its background schedule
        // immediately. We keep userDriver nil so Sparkle uses its built-in
        // standard user driver (a small window offering to download + install).
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Manual "Check for Updates…" menu action. Defers to Sparkle's standard
    /// controller so the user sees the familiar update window.
    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }
}
