#!/usr/bin/env bash
# Builds InputMetrics with SwiftPM, wraps it in an .app bundle, signs it, and installs it.
# Set SIGN_IDENTITY to a self-signed code-signing certificate name to keep
# Input Monitoring/Accessibility grants across rebuilds. Defaults to ad-hoc.
set -euo pipefail

cd "$(dirname "$0")/.."
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DEST="${DEST:-/Applications}"
SRC=InputMetrics/InputMetrics
APP=.build/InputMetrics.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/InputMetrics"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/InputMetrics"

sed -e 's/$(DEVELOPMENT_LANGUAGE)/en/' \
    -e 's/$(EXECUTABLE_NAME)/InputMetrics/' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.inputmetrics.InputMetrics/' \
    -e 's/$(PRODUCT_NAME)/InputMetrics/' \
    -e 's/$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/' \
    -e 's/$(MACOSX_DEPLOYMENT_TARGET)/14.0/' \
    "$SRC/Info.plist" > "$APP/Contents/Info.plist"

ICON="$(ls "$SRC"/Media.xcassets/AppIcon.appiconset/*1024x1024@1x.png | head -1)"
ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$ICON" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"

codesign --force --sign "$SIGN_IDENTITY" "$APP"

osascript -e 'tell application "InputMetrics" to quit' >/dev/null 2>&1 || true
rm -rf "$DEST/InputMetrics.app"
cp -R "$APP" "$DEST/InputMetrics.app"
echo "Installed $DEST/InputMetrics.app"
