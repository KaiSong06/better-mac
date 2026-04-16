#!/usr/bin/env bash
#
# One-time setup helper for notarization.
#
# Run this once per machine to store your Apple ID + app-specific password in
# the Keychain so `xcrun notarytool` can authenticate non-interactively in CI
# and in scripts/release.sh.
#
# Prerequisites:
#   - Apple Developer Program membership
#   - An app-specific password generated at https://appleid.apple.com
#     (Sign-In and Security → App-Specific Passwords → +)
#   - Your Apple ID email
#   - Your 10-char Team ID (find it at https://developer.apple.com/account)
#
# Usage:
#   ./scripts/setup-notary.sh
#
set -euo pipefail

PROFILE="${NOTARY_KEYCHAIN_PROFILE:-better-mac-notary}"

echo "This will store notarization credentials under keychain profile: $PROFILE"
echo
read -r -p "Apple ID (email): " APPLE_ID
read -r -p "Team ID (10 chars): " TEAM
read -r -s -p "App-specific password: " APP_PW
echo

xcrun notarytool store-credentials "$PROFILE" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM" \
  --password "$APP_PW"

echo
echo "Saved. Now add these to your shell profile (~/.zshrc):"
echo
echo "  export NOTARY_KEYCHAIN_PROFILE=\"$PROFILE\""
echo "  export TEAM_ID=\"$TEAM\""
echo "  export DEVELOPER_ID_APPLICATION=\"Developer ID Application: YOUR_NAME ($TEAM)\""
echo
echo "Verify the DEVELOPER_ID_APPLICATION string by running:"
echo "  security find-identity -v -p codesigning | grep 'Developer ID Application'"
