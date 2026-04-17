# NotchFree

A lightweight macOS utility that brings two iPhone-style niceties to your Mac:

1. **Dynamic Island** — hover the top-middle of the screen and the notch briefly puffs out (peek); hold for ¾ of a second and the panel drops down into the full media UI (artwork, title, artist, play/pause/skip, and seek bar). When audio is playing the collapsed island widens into a compact pill showing the album cover on the left and an animated waveform on the right (frozen when paused). Blends seamlessly into the physical notch on notched MacBooks; falls back to a floating pill on non-notched displays.
2. **iPhone-style volume HUD** — the native macOS volume HUD is suppressed. In its place, a tall pill with a frosted vibrancy track appears flush against the right edge of the screen, showing the current volume, the output device icon (built-in speakers, AirPods, Bluetooth, USB, AirPlay), and the device name. The speaker glyph inverts color across the fill boundary, matching the iOS 17+ volume indicator.

Runs as a menu bar agent with no Dock icon. Auto-updates via Sparkle.

**Website:** https://KaiSong06.github.io/NotchFree
**Download:** https://github.com/KaiSong06/NotchFree/releases/latest

---

## Install

1. Download the latest DMG from [Releases](https://github.com/KaiSong06/NotchFree/releases/latest).
2. Open the DMG and drag `NotchFree.app` into `/Applications`.
3. Launch the app. Grant Accessibility permission when prompted (required for the volume HUD feature to intercept hardware volume keys; the Dynamic Island works without it).
4. Optionally toggle **Open at Login** from the menu bar icon.

---

## Build from source

Requirements:
- macOS 14 (Sonoma) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

```bash
xcodegen generate
xcodebuild -project better-mac.xcodeproj -scheme better-mac -configuration Debug build
open "$(xcodebuild -project better-mac.xcodeproj -scheme better-mac -showBuildSettings 2>/dev/null | awk -F'=' '/BUILT_PRODUCTS_DIR/ {gsub(/ /,"",$2); print $2; exit}')/NotchFree.app"
```

---

## Release pipeline

### One-time setup (per machine)

1. **Install tooling**
   ```bash
   brew install xcodegen create-dmg
   ```

2. **Create a Developer ID Application certificate.** At https://developer.apple.com/account → Certificates → `+` → **Developer ID Application**. Download the `.cer` and double-click to add it to the login keychain. Verify:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

3. **Generate a Sparkle EdDSA signing key.** The private key stays in your login keychain; the public key is already in `project.yml` → `SUPublicEDKey`. If you ever rotate the key, regenerate and update the plist entry.

4. **Set up notarization credentials.**
   ```bash
   ./scripts/setup-notary.sh
   ```
   This stores an Apple ID + app-specific password under a keychain profile (default: `better-mac-notary`). Generate the app-specific password at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.

5. **Export required env vars** (e.g. in `~/.zshrc`):
   ```bash
   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID1234)"
   export TEAM_ID="TEAMID1234"
   export NOTARY_KEYCHAIN_PROFILE="better-mac-notary"
   ```

### Cut a release

```bash
./scripts/release.sh 0.1.0
```

This will:
1. Bump `MARKETING_VERSION` in `project.yml` and increment `CURRENT_PROJECT_VERSION`.
2. Regenerate the Xcode project.
3. Archive → export a Developer ID signed `NotchFree.app`.
4. Submit the `.app` to Apple notarization (waits for the ticket).
5. Staple the ticket.
6. Package as `NotchFree-0.1.0.dmg` (drag-to-Applications DMG via `create-dmg`).
7. Sign + notarize + staple the DMG.
8. Compute the Sparkle EdDSA signature of the DMG and append a new `<item>` to `docs/appcast.xml`.

Then commit and push:

```bash
git add project.yml docs/appcast.xml
git commit -m "release: v0.1.0"
git tag v0.1.0
git push && git push --tags
gh release create v0.1.0 --generate-notes build/NotchFree-0.1.0.dmg
```

GitHub Pages (serving `/docs` on `main`) then has the updated `appcast.xml` live at https://KaiSong06.github.io/NotchFree/appcast.xml, so existing installs pick up the update on their next Sparkle check.

---

## Architecture

- **Media info** — uses the private `MediaRemote.framework` (via `dlopen` + `CFBundleGetFunctionPointerForName`) to subscribe to system-wide Now Playing updates. Falls back to AppleScript polling of Spotify when MediaRemote goes silent.
- **Notch detection** — uses `NSScreen.safeAreaInsets` plus `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` to compute the notch rect on any notched MacBook. Non-notched displays render a floating pill instead.
- **Volume key handling** — a `CGEventTap` at `.cgSessionEventTap` intercepts `NSSystemDefined` subtype-8 events (the ones the hardware volume keys produce) and returns `nil` from the callback so macOS never sees them. The interceptor then sets the volume via `AudioObjectSetPropertyData` on `kAudioDevicePropertyVolumeScalar` of the current default output device.
- **Output device classification** — uses `kAudioDevicePropertyTransportType` plus a name-contains check for "AirPods" / "Beats".
- **Auto-updates** — [Sparkle 2](https://sparkle-project.org) reads `SUFeedURL` and `SUPublicEDKey` from `Info.plist`. The private EdDSA key lives in the Keychain; `sign_update` (bundled in the Sparkle SPM artifact) produces the signature for each DMG during release.

## Project structure

```
better-mac/
├── better-mac/
│   ├── App/          # App lifecycle, status bar, settings, updater
│   ├── Island/       # Dynamic Island NSPanel + SwiftUI content
│   ├── Media/        # MediaRemote bridge + Spotify fallback
│   ├── Volume/       # CGEventTap + CoreAudio + HUD pill
│   ├── Support/      # Logger, Permissions, NSScreen+Notch
│   └── Resources/    # Info.plist, Assets
├── better-macTests/  # Unit tests
├── docs/             # GitHub Pages site + appcast.xml
├── scripts/          # release.sh, setup-notary.sh, generate-icon.py
└── project.yml       # XcodeGen spec
```

## Acknowledgements

Technique references (no code copied):
- [Atoll](https://github.com/Ebullioscopic/Atoll) — MediaRemote dlopen pattern, notch geometry
- [NotchDrop](https://github.com/Lakr233/NotchDrop) — notch width math
- [volumeHUD](https://github.com/dannystewart/volumeHUD) — CGEventTap for volume keys
- [volume-grid](https://github.com/euxx/volume-grid) — CoreAudio default-output listener
- [Sparkle](https://sparkle-project.org) — auto-update framework
