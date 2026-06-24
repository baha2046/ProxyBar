#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.2}"
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-develop}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/baha2046/ProxyBar/releases/latest/download/appcast.xml}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"
APP_DIR="$ROOT_DIR/.build/ProxyBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
DIST_DIR="$ROOT_DIR/dist"
ZIP_PATH="$DIST_DIR/ProxyBar-$VERSION.zip"
NOTARY_ZIP_PATH="$DIST_DIR/ProxyBar-$VERSION-notary.zip"
APPCAST_PATH="$DIST_DIR/appcast.xml"
APPCAST_INPUT_DIR="$DIST_DIR/.sparkle-appcast"

if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "SPARKLE_PUBLIC_ED_KEY is required for Sparkle updates." >&2
    exit 1
fi

cd "$ROOT_DIR"
rm -rf "$APP_DIR"
rm -rf "$APPCAST_INPUT_DIR"
rm -f "$ZIP_PATH" "$NOTARY_ZIP_PATH" "$APPCAST_PATH"

cleanup_failed_release() {
    rm -rf "$APPCAST_INPUT_DIR"
    rm -f "$ZIP_PATH" "$NOTARY_ZIP_PATH" "$APPCAST_PATH"
}
trap cleanup_failed_release ERR

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

SPARKLE_FRAMEWORK="$(
    find "$ROOT_DIR/.build/artifacts" -path '*/Sparkle.framework' -type d -print -quit
)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework was not found under .build/artifacts." >&2
    exit 1
fi

if [[ -z "$SPARKLE_GENERATE_APPCAST" ]]; then
    SPARKLE_GENERATE_APPCAST="$(
        find "$ROOT_DIR/.build/artifacts" -path '*/bin/generate_appcast' -type f -print -quit
    )"
fi
if [[ -z "$SPARKLE_GENERATE_APPCAST" || ! -x "$SPARKLE_GENERATE_APPCAST" ]]; then
    echo "Sparkle generate_appcast tool was not found or is not executable." >&2
    exit 1
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$DIST_DIR"
cp "$ROOT_DIR/.build/release/ProxyBar" "$MACOS_DIR/ProxyBar"
swift run -c release IconGenerator "$RESOURCES_DIR/AppIcon.icns"
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"

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
    <key>SUFeedURL</key>
    <string>$SPARKLE_FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_ED_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <true/>
</dict>
</plist>
PLIST

SPARKLE_VERSION_DIR="$FRAMEWORKS_DIR/Sparkle.framework/Versions/B"

/usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
/usr/bin/codesign --force --options runtime --timestamp \
    --preserve-metadata=entitlements \
    --sign "$SIGNING_IDENTITY" "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
/usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$SPARKLE_VERSION_DIR/Autoupdate"
/usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$SPARKLE_VERSION_DIR/Updater.app"
/usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework"

/usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

/usr/bin/ditto -c -k --norsrc --keepParent "$APP_DIR" "$NOTARY_ZIP_PATH"
/usr/bin/xcrun notarytool submit "$NOTARY_ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP_DIR"
/usr/bin/xcrun stapler validate "$APP_DIR"

rm -f "$NOTARY_ZIP_PATH"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"

mkdir -p "$APPCAST_INPUT_DIR"
cp "$ZIP_PATH" "$APPCAST_INPUT_DIR/"
"$SPARKLE_GENERATE_APPCAST" \
    -o "$APPCAST_PATH" \
    --download-url-prefix "https://github.com/baha2046/ProxyBar/releases/download/v$VERSION/" \
    "$APPCAST_INPUT_DIR"

if ! grep -F 'sparkle:edSignature=' "$APPCAST_PATH" >/dev/null; then
    echo "Generated appcast does not contain an EdDSA update signature." >&2
    exit 1
fi

rm -rf "$APPCAST_INPUT_DIR"
trap - ERR

echo "Created $APP_DIR"
echo "Created $ZIP_PATH"
echo "Created $APPCAST_PATH"
echo "Signed with identity: $SIGNING_IDENTITY"
echo "Notarized with keychain profile: $NOTARY_PROFILE"
echo "SHA-256:"
/usr/bin/shasum -a 256 "$ZIP_PATH"
