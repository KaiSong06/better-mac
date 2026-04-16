#!/usr/bin/env bash
#
# Release pipeline for NotchFree.
#
# Usage:
#   ./scripts/release.sh <version>   # e.g. ./scripts/release.sh 0.1.0
#
# Runs the full Developer-ID-signed, notarized, Sparkle-ready release flow:
#   1. Bump MARKETING_VERSION + CURRENT_PROJECT_VERSION in project.yml
#   2. Regenerate the Xcode project
#   3. Build Release config, archived + exported as a signed .app
#   4. Notarize via notarytool (requires a stored keychain profile)
#   5. Staple the notarization ticket to the .app
#   6. Package as a DMG via create-dmg
#   7. Sign the DMG (Developer ID)
#   8. Notarize the DMG (optional but belt-and-suspenders)
#   9. sign_update the DMG with the Sparkle EdDSA private key
#  10. Append a new <item> to docs/appcast.xml
#
# Requires (one-time setup):
#   - Developer ID Application certificate in the Keychain
#   - `xcrun notarytool store-credentials $NOTARY_KEYCHAIN_PROFILE ...` run once
#   - Sparkle EdDSA keys generated into the Keychain (generate_keys)
#   - create-dmg: `brew install create-dmg`
#
# Required environment variables (put these in ~/.zshrc or similar):
#   DEVELOPER_ID_APPLICATION   — full identity string (see `security find-identity -v`)
#   TEAM_ID                    — Apple Developer Team ID (10 chars)
#   NOTARY_KEYCHAIN_PROFILE    — name used in notarytool store-credentials
#
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Xcode target / scheme names stayed `better-mac` — renaming them would churn
# the whole project file. The produced binary is branded via PRODUCT_NAME in
# project.yml, so `APP_NAME` is what users see; `SCHEME` is the internal
# xcodebuild handle.
SCHEME="better-mac"
PROJECT_NAME="better-mac"    # .xcodeproj filename
APP_NAME="NotchFree"         # user-facing .app / DMG brand
BUNDLE_ID="com.KaiSong06.NotchFree"
REPO_NAME="better-mac"       # GitHub repo slug (different from app brand)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APPCAST_PATH="$ROOT/docs/appcast.xml"
DOWNLOAD_URL_BASE="${DOWNLOAD_URL_BASE:-https://github.com/KaiSong06/$REPO_NAME/releases/download}"

# Sparkle tools resolved after SPM sync.
SPARKLE_BIN_DIR=""

# -----------------------------------------------------------------------------
# Arg validation
# -----------------------------------------------------------------------------

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>    e.g. $0 0.1.0" >&2
  exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be semver (X.Y.Z), got: $VERSION" >&2
  exit 1
fi

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION — full Developer ID cert name}"
: "${TEAM_ID:?Set TEAM_ID — your 10-char Apple Developer Team ID}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE — run 'xcrun notarytool store-credentials' first}"

for tool in xcodegen xcodebuild xcrun create-dmg plutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool not found: $tool" >&2
    exit 1
  fi
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log() { printf "\n\033[1;34m▶\033[0m %s\n" "$*"; }
ok()  { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Step 1: Bump version
# -----------------------------------------------------------------------------

log "Bumping version to $VERSION"
# Bump MARKETING_VERSION
python3 - "$VERSION" <<'PY'
import sys, re, pathlib
version = sys.argv[1]
path = pathlib.Path("project.yml")
text = path.read_text()
new_text, n = re.subn(r'MARKETING_VERSION:\s*"[^"]*"', f'MARKETING_VERSION: "{version}"', text, count=1)
if n != 1:
    raise SystemExit("failed to find MARKETING_VERSION in project.yml")
# Bump CURRENT_PROJECT_VERSION by 1 each release
m = re.search(r'CURRENT_PROJECT_VERSION:\s*"(\d+)"', new_text)
if not m:
    raise SystemExit("failed to find CURRENT_PROJECT_VERSION in project.yml")
build_num = int(m.group(1)) + 1
new_text = re.sub(r'CURRENT_PROJECT_VERSION:\s*"\d+"', f'CURRENT_PROJECT_VERSION: "{build_num}"', new_text, count=1)
path.write_text(new_text)
print(f"MARKETING_VERSION={version}, CURRENT_PROJECT_VERSION={build_num}")
PY
ok "project.yml updated"

# -----------------------------------------------------------------------------
# Step 2: Regenerate Xcode project
# -----------------------------------------------------------------------------

log "Regenerating Xcode project"
cd "$ROOT"
xcodegen generate > /dev/null
ok "xcodeproj regenerated"

# -----------------------------------------------------------------------------
# Step 3: Resolve Sparkle package + locate tools
# -----------------------------------------------------------------------------

log "Resolving Sparkle package"
xcodebuild -project "$PROJECT_NAME.xcodeproj" -scheme "$SCHEME" -resolvePackageDependencies > /dev/null
# OBJROOT looks like .../DerivedData/<project-hash>/Build/Intermediates.noindex
# Trim the trailing /Build/... to get the per-project DerivedData root, which
# contains SourcePackages/ as a sibling of Build/.
DERIVED="$(xcodebuild -project "$PROJECT_NAME.xcodeproj" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
  | awk -F'=' '/ OBJROOT = / {gsub(/ /,"",$2); print $2}' \
  | sed 's|/Build/Intermediates.noindex||' )"
SPARKLE_BIN_DIR="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_BIN_DIR/sign_update" ]] || die "sign_update not found at $SPARKLE_BIN_DIR/sign_update"
ok "Sparkle tools: $SPARKLE_BIN_DIR"

# -----------------------------------------------------------------------------
# Step 4: Archive and export the Release .app
# -----------------------------------------------------------------------------

rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR"

log "Archiving Release build"
xcodebuild \
  -project "$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  CODE_SIGN_STYLE=Manual \
  ONLY_ACTIVE_ARCH=NO \
  archive \
  > "$BUILD_DIR/archive.log" 2>&1 \
  || { tail -80 "$BUILD_DIR/archive.log"; die "archive failed"; }
ok "Archive at $ARCHIVE_PATH"

log "Exporting Developer ID .app"
EXPORT_PLIST="$BUILD_DIR/exportOptions.plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$DEVELOPER_ID_APPLICATION</string>
</dict>
</plist>
PLIST
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  > "$BUILD_DIR/export.log" 2>&1 \
  || { tail -80 "$BUILD_DIR/export.log"; die "export failed"; }
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || die ".app not found at $APP_PATH"
ok "Exported $APP_PATH"

# -----------------------------------------------------------------------------
# Step 5: Verify codesign
# -----------------------------------------------------------------------------

log "Verifying codesign"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -5
ok "Codesign verified"

# -----------------------------------------------------------------------------
# Step 6: Notarize the .app
# -----------------------------------------------------------------------------

APP_ZIP="$BUILD_DIR/$APP_NAME-$VERSION-notarize.zip"
log "Zipping .app for notarization"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

log "Submitting .app to Apple notarization"
xcrun notarytool submit "$APP_ZIP" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait \
  2>&1 | tee "$BUILD_DIR/notary.log" \
  || die "notarytool submit failed"
grep -q "status: Accepted" "$BUILD_DIR/notary.log" \
  || { xcrun notarytool log "$(grep -oE 'id: [a-f0-9-]+' "$BUILD_DIR/notary.log" | head -1 | awk '{print $2}')" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" 2>&1 | tail -40; die "notarization failed"; }

log "Stapling notarization ticket to .app"
xcrun stapler staple "$APP_PATH" 2>&1 | tail -5
xcrun stapler validate "$APP_PATH" 2>&1 | tail -3
ok "Notarization stapled"

# -----------------------------------------------------------------------------
# Step 7: Build the DMG
# -----------------------------------------------------------------------------

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
log "Building DMG"
rm -f "$DMG_PATH"
create-dmg \
  --volname "$APP_NAME $VERSION" \
  --window-pos 200 120 \
  --window-size 540 340 \
  --icon-size 96 \
  --icon "$APP_NAME.app" 140 160 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 400 160 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH" \
  2>&1 | tail -10 || true
[[ -f "$DMG_PATH" ]] || die "DMG was not created"
ok "DMG at $DMG_PATH"

log "Signing DMG"
codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG_PATH"

log "Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait \
  2>&1 | tee "$BUILD_DIR/notary-dmg.log" \
  || die "DMG notarytool submit failed"
grep -q "status: Accepted" "$BUILD_DIR/notary-dmg.log" \
  || die "DMG notarization failed"
xcrun stapler staple "$DMG_PATH" 2>&1 | tail -5
xcrun stapler validate "$DMG_PATH" 2>&1 | tail -3
ok "DMG notarized + stapled"

# -----------------------------------------------------------------------------
# Step 8: Sign the DMG for Sparkle + build appcast entry
# -----------------------------------------------------------------------------

log "Signing DMG for Sparkle updates"
SIGN_OUT="$("$SPARKLE_BIN_DIR/sign_update" "$DMG_PATH")"
# Output looks like: sparkle:edSignature="..." length="..."
DMG_SIZE="$(stat -f%z "$DMG_PATH")"
DOWNLOAD_URL="$DOWNLOAD_URL_BASE/v$VERSION/$DMG_NAME"
PUBDATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"

log "Updating $APPCAST_PATH"
mkdir -p "$(dirname "$APPCAST_PATH")"
python3 - "$APPCAST_PATH" "$VERSION" "$DOWNLOAD_URL" "$DMG_SIZE" "$SIGN_OUT" "$PUBDATE" <<'PY'
import sys, pathlib, re
appcast_path, version, url, size, sign_out, pubdate = sys.argv[1:]
sig_match = re.search(r'sparkle:edSignature="([^"]+)"', sign_out)
if not sig_match:
    raise SystemExit("could not parse sparkle:edSignature from sign_update output")
signature = sig_match.group(1)

path = pathlib.Path(appcast_path)
if not path.exists():
    path.write_text('''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>better-mac Updates</title>
    <link>https://KaiSong06.github.io/better-mac/appcast.xml</link>
    <description>Release feed for better-mac</description>
    <language>en</language>
  </channel>
</rss>
''')

xml = path.read_text()
item = f'''    <item>
      <title>Version {version}</title>
      <pubDate>{pubdate}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h3>better-mac {version}</h3>
        <p>See <a href="https://github.com/KaiSong06/better-mac/releases/tag/v{version}">release notes</a>.</p>
      ]]></description>
      <enclosure
        url="{url}"
        length="{size}"
        type="application/octet-stream"
        sparkle:edSignature="{signature}"
      />
    </item>
'''
# Insert the new <item> just before </channel>
if item.strip() in xml:
    print("item already present; skipping")
else:
    xml = xml.replace("</channel>", item + "  </channel>")
    path.write_text(xml)
    print(f"appcast updated at {path}")
PY

ok "appcast updated"

# -----------------------------------------------------------------------------
# Step 9: Summary
# -----------------------------------------------------------------------------

printf "\n\033[1;32m╭──────────────────────────────────────────────╮\033[0m\n"
printf "\033[1;32m│  Release v%s built successfully          │\033[0m\n" "$VERSION"
printf "\033[1;32m╰──────────────────────────────────────────────╯\033[0m\n\n"
echo "DMG:       $DMG_PATH"
echo "Size:      $DMG_SIZE bytes"
echo "Appcast:   $APPCAST_PATH"
echo ""
echo "Next steps:"
echo "  1. Commit the version bump + updated appcast:"
echo "       git add project.yml docs/appcast.xml"
echo "       git commit -m \"release: v$VERSION\""
echo "       git tag v$VERSION"
echo "       git push && git push --tags"
echo "  2. Create the GitHub release with the DMG attached:"
echo "       gh release create v$VERSION --generate-notes \"$DMG_PATH\""
echo "  3. Ensure the appcast is live at https://KaiSong06.github.io/better-mac/appcast.xml"
echo "     (GitHub Pages serves /docs on the default branch.)"
