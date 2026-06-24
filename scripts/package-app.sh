#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.2}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-develop}"
APP_DIR="$ROOT_DIR/.build/ProxyBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DIST_DIR="$ROOT_DIR/dist"
ZIP_PATH="$DIST_DIR/ProxyBar-$VERSION.zip"
NOTARY_ZIP_PATH="$DIST_DIR/ProxyBar-$VERSION-notary.zip"

cd "$ROOT_DIR"
rm -rf "$APP_DIR"
rm -f "$ZIP_PATH" "$NOTARY_ZIP_PATH"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    if ! SIGNING_IDENTITY="$(
        /usr/bin/security find-identity -v -p codesigning |
            awk -F '"' \
                '/Developer ID Application/ && !found { print $2; found=1 }'
    )"; then
        echo "Failed to query Developer ID signing identities." >&2
        echo "Set SIGNING_IDENTITY to override automatic discovery." >&2
        exit 1
    fi
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "No Developer ID Application signing identity was found." >&2
    echo "Install a valid certificate or set SIGNING_IDENTITY explicitly." >&2
    exit 1
fi

swift build -c release --product ProxyBar

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

/usr/bin/codesign --force --deep --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

/usr/bin/ditto -c -k --norsrc --keepParent "$APP_DIR" "$NOTARY_ZIP_PATH"
/usr/bin/xcrun notarytool submit "$NOTARY_ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP_DIR"
/usr/bin/xcrun stapler validate "$APP_DIR"

rm -f "$NOTARY_ZIP_PATH"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Created $APP_DIR"
echo "Created $ZIP_PATH"
echo "Signed with identity: $SIGNING_IDENTITY"
echo "Notarized with keychain profile: $NOTARY_PROFILE"
echo "SHA-256:"
/usr/bin/shasum -a 256 "$ZIP_PATH"
