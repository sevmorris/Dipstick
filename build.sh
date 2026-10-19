#!/usr/bin/env bash
set -euo pipefail

# Build Dipstick.app into build/, for running on this Mac.
#
# A Swift package, not an Xcode project: swift builds the binary, and
# scripts/assemble-app.sh builds the bundle around it, as it does for
# release.sh. The bundle is signed ad hoc and not notarized; release.sh signs
# with the Developer ID and notarizes.

cd "$(dirname "$0")"

APP_NAME="Dipstick"
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

scripts/assemble-app.sh "$BIN_DIR/$APP_NAME" "$APP_PATH" "$VERSION" "$MIN_MACOS"

codesign --force --sign - "$APP_PATH"

echo ""
echo "Built $APP_PATH ($VERSION)"
echo "Run with: open $APP_PATH"
