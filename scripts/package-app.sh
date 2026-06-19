#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP_DIR="$ROOT_DIR/.build/ProxyBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DIST_DIR="$ROOT_DIR/dist"
ZIP_PATH="$DIST_DIR/ProxyBar-$VERSION.zip"

cd "$ROOT_DIR"
swift build -c release --product ProxyBar

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DIST_DIR"
cp "$ROOT_DIR/.build/release/ProxyBar" "$MACOS_DIR/ProxyBar"
swift run -c release IconGenerator "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ProxyBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.ericchan.ProxyBar</string>
    <key>CFBundleName</key>
    <string>ProxyBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Created $APP_DIR"
echo "Created $ZIP_PATH"
echo "Signed with identity: $SIGNING_IDENTITY"
echo "SHA-256:"
/usr/bin/shasum -a 256 "$ZIP_PATH"
