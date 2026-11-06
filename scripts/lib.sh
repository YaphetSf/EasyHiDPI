# shellcheck shell=bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME=EasyHiDPI
APP_ICON="$PROJECT_ROOT/Packaging/AppIcon.icns"
INSTALLED_APP="/Applications/$APP_NAME.app"
if [[ -f "$PROJECT_ROOT/scripts/local.env" ]]; then
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/local.env"
fi
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

unlock_signing_keychain() {
    if [[ -f "$SIGNING_KEYCHAIN" ]]; then
        /usr/bin/security unlock-keychain -p "" "$SIGNING_KEYCHAIN"
    fi
}

has_signing_identity() {
    [[ -n "$CODESIGN_IDENTITY" ]] &&
        /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -F -- "$CODESIGN_IDENTITY" >/dev/null
}

# stage_app <debug|release> <destination.app>
stage_app() {
    local configuration=$1 destination=$2 bin_directory
    (
        cd "$PROJECT_ROOT"
        if [[ ! -f "$APP_ICON" ]]; then
            swift "$PROJECT_ROOT/scripts/generate-app-icon.swift"
        fi
        swift build --configuration "$configuration"
    )
    bin_directory=$(cd "$PROJECT_ROOT" && swift build --configuration "$configuration" --show-bin-path)
    mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources"
    cp "$PROJECT_ROOT/Packaging/Info.plist" "$destination/Contents/Info.plist"
    cp "$bin_directory/$APP_NAME" "$destination/Contents/MacOS/$APP_NAME"
    cp "$APP_ICON" "$destination/Contents/Resources/AppIcon.icns"
}

# install_app <source.app>
install_app() {
    local source_app=$1 running_pid
    while read -r running_pid; do
        [[ -n "$running_pid" ]] && /bin/kill "$running_pid" 2>/dev/null || true
    done < <(/usr/bin/pgrep -x "$APP_NAME" || true)

    rm -rf "$INSTALLED_APP"
    ditto "$source_app" "$INSTALLED_APP"
    codesign --verify --deep --strict "$INSTALLED_APP"
    "$LSREGISTER" -f "$INSTALLED_APP" >/dev/null 2>&1 || true
    /usr/bin/open "$INSTALLED_APP"
    echo "Installed and launched $INSTALLED_APP"
}
