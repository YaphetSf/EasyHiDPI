#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DIST_DIRECTORY="$PROJECT_ROOT/dist"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-notary}"

notarize() {
    /usr/bin/xcrun notarytool submit "$1" \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
        ${SIGNING_KEYCHAIN:+--keychain "$SIGNING_KEYCHAIN"} \
        --wait
}

unlock_signing_keychain
if ! has_signing_identity; then
    echo "Code-signing identity not found: set CODESIGN_IDENTITY in the environment or scripts/local.env" >&2
    exit 1
fi

echo "==> testing"
(cd "$PROJECT_ROOT" && swift test)

echo "==> generating app icon"
swift "$PROJECT_ROOT/scripts/generate-app-icon.swift"

STAGING_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/easyhidpi-release.XXXXXX")
trap 'rm -rf "$STAGING_ROOT"' EXIT
STAGED_APP="$STAGING_ROOT/$APP_NAME.app"

echo "==> building"
stage_app release "$STAGED_APP"

echo "==> signing"
codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

echo "==> notarizing app"
NOTARY_ZIP="$STAGING_ROOT/notary.zip"
ditto -c -k --keepParent "$STAGED_APP" "$NOTARY_ZIP"
notarize "$NOTARY_ZIP"
/usr/bin/xcrun stapler staple "$STAGED_APP"
spctl --assess --type execute --verbose=2 "$STAGED_APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$STAGED_APP/Contents/Info.plist")
DMG_PATH="$DIST_DIRECTORY/$APP_NAME-$VERSION.dmg"

echo "==> creating DMG"
mkdir -p "$DIST_DIRECTORY"
rm -f "$DMG_PATH"
DMG_LAYOUT="$STAGING_ROOT/dmg-layout"
mkdir -p "$DMG_LAYOUT"
ditto "$STAGED_APP" "$DMG_LAYOUT/$APP_NAME.app"
ln -s /Applications "$DMG_LAYOUT/Applications"
/usr/bin/hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$DMG_LAYOUT" -ov -format UDZO "$DMG_PATH"
codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"

echo "==> notarizing DMG"
notarize "$DMG_PATH"
/usr/bin/xcrun stapler staple "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

echo "==> installing"
install_app "$STAGED_APP"

echo "DMG: $DMG_PATH"
