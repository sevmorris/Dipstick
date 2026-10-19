#!/usr/bin/env bash
set -euo pipefail

# Build Dipstick.app into build/, for running on this Mac.
#
# A Swift package, not an Xcode project: swift builds the binary, and this
# script assembles the bundle around it, as PasswordGen's release.sh does.
# The bundle is signed ad hoc and not notarized; a release.sh will do that
# when Dipstick has releases.

cd "$(dirname "$0")"

APP_NAME="Dipstick"
BUNDLE_ID="io.github.sevmorris.Dipstick"
APP_PATH="build/${APP_NAME}.app"

# The version lives once, in DipstickApp.swift, and the minimum macOS once,
# in Package.swift; the Info.plist is written from both.
VERSION=$(sed -n 's/^let appVersion = "\(.*\)"$/\1/p' "Sources/${APP_NAME}/${APP_NAME}App.swift")
MIN_MACOS=$(sed -n 's/.*\.macOS("\([0-9.]*\)").*/\1/p' Package.swift)
[[ -n "$VERSION" ]]   || { echo "No appVersion in ${APP_NAME}App.swift" >&2; exit 1; }
[[ -n "$MIN_MACOS" ]] || { echo "No .macOS(\"…\") platform in Package.swift" >&2; exit 1; }

swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
[[ -x "$BIN_DIR/$APP_NAME" ]] || { echo "swift build produced no $APP_NAME binary" >&2; exit 1; }

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$BIN_DIR/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"

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
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Seven Morris. MIT License.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null

codesign --force --sign - "$APP_PATH"

echo ""
echo "Built $APP_PATH ($VERSION)"
echo "Run with: open $APP_PATH"
