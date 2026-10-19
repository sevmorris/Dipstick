#!/usr/bin/env bash
set -euo pipefail

# assemble-app.sh BINARY APP VERSION MIN_MACOS
#
# Builds Dipstick.app at APP around a binary swift has built: the executable,
# the icon, and the Info.plist. It does not sign.
#
# build.sh and release.sh both call it, so the bundle a local build makes and
# the bundle a release ships are the same bundle. Each writing its own
# Info.plist is two copies of one list of keys, and a key added to one alone
# is how a release would ship with a Dock icon (no LSUIElement) or with no
# minimum macOS for the update check to read.

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 BINARY APP VERSION MIN_MACOS" >&2
    exit 2
fi

BINARY=$1
APP_PATH=$2
VERSION=$3
MIN_MACOS=$4

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Dipstick"
BUNDLE_ID="io.github.sevmorris.Dipstick"
ICON="$ROOT/assets/AppIcon.icns"

[[ -x "$BINARY" ]] || { echo "No executable at $BINARY" >&2; exit 1; }
[[ -f "$ICON" ]]   || { echo "No icon at ${ICON#"$ROOT"/} — run tools/icon/make-appicon.py" >&2; exit 1; }

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$ICON" "$APP_PATH/Contents/Resources/AppIcon.icns"

# LSUIElement: a menu bar app, with no Dock icon and no app menu.
cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Seven Morris. MIT License.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
