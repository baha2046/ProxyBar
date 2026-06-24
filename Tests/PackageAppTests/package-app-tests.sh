#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/package-app.sh"
TMP_BASE="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "${TMP_BASE%/}/proxybar-package-tests.XXXXXX")"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_log_contains() {
    local log_path="$1"
    local expected="$2"
    if ! grep -F -- "$expected" "$log_path" >/dev/null; then
        echo "Command log:" >&2
        cat "$log_path" >&2
        fail "expected command log to contain: $expected"
    fi
}

assert_log_excludes() {
    local log_path="$1"
    local unexpected="$2"
    if [[ ! -f "$log_path" ]]; then
        return
    fi
    if grep -F -- "$unexpected" "$log_path" >/dev/null; then
        fail "expected command log not to contain: $unexpected"
    fi
}

create_fixture() {
    local name="$1"
    local fixture_dir="$TEST_ROOT/$name"
    local mock_bin="$fixture_dir/mock-bin"

    mkdir -p "$fixture_dir/scripts" "$mock_bin"
    local sparkle_framework="$fixture_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    local sparkle_tools="$fixture_dir/.build/artifacts/sparkle/Sparkle/bin"
    mkdir -p \
        "$sparkle_framework/Versions/B/XPCServices/Installer.xpc" \
        "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc" \
        "$sparkle_framework/Versions/B/Updater.app" \
        "$sparkle_tools"
    : > "$sparkle_framework/Versions/B/Sparkle"
    : > "$sparkle_framework/Versions/B/Autoupdate"
    ln -s B "$sparkle_framework/Versions/Current"
    ln -s Versions/Current/Sparkle "$sparkle_framework/Sparkle"
    ln -s Versions/Current/Resources "$sparkle_framework/Resources"

    cat > "$sparkle_tools/generate_appcast" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf 'generate_appcast' >> "$COMMAND_LOG"
printf ' %q' "$@" >> "$COMMAND_LOG"
printf '\n' >> "$COMMAND_LOG"

if [[ "${MOCK_APPCAST_FAILURE:-0}" == "1" ]]; then
    exit 1
fi

output_path=""
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
        output_path="$2"
        shift 2
    else
        shift
    fi
done

mkdir -p "$(dirname "$output_path")"
if [[ "${MOCK_APPCAST_UNSIGNED:-0}" == "1" ]]; then
    cat > "$output_path" <<'XML'
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><item><enclosure/></item></channel>
</rss>
XML
else
    cat > "$output_path" <<'XML'
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><item><enclosure sparkle:edSignature="test-signature"/></item></channel>
</rss>
XML
fi
MOCK
    chmod +x "$sparkle_tools/generate_appcast"

    {
        head -n 1 "$SCRIPT_PATH"
        tail -n +2 "$SCRIPT_PATH" |
            /usr/bin/sed "s#/usr/bin/#$mock_bin/#g"
    } > "$fixture_dir/scripts/package-app.sh"
    chmod +x "$fixture_dir/scripts/package-app.sh"

    cat > "$mock_bin/mock-command" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

command_name="$(basename "$0")"
printf '%s' "$command_name" >> "$COMMAND_LOG"
printf ' %q' "$@" >> "$COMMAND_LOG"
printf '\n' >> "$COMMAND_LOG"

case "$command_name" in
    swift)
        if [[ "${1:-}" == "build" ]]; then
            mkdir -p "$PROJECT_ROOT/.build/release"
            : > "$PROJECT_ROOT/.build/release/ProxyBar"
        elif [[ "${1:-}" == "run" ]]; then
            output_path="${!#}"
            mkdir -p "$(dirname "$output_path")"
            : > "$output_path"
        fi
        ;;
    security)
        if [[ "${MOCK_SECURITY_EMPTY:-0}" != "1" ]]; then
            echo '  1) ABCDEF1234567890 "Developer ID Application: Example (TEAMID)"'
            echo "     1 valid identities found"
        else
            echo "     0 valid identities found"
        fi
        ;;
    ditto)
        if [[ -d "${1:-}" && "${1:-}" != -* ]]; then
            cp -R "$1" "$2"
        else
            output_path="${!#}"
            mkdir -p "$(dirname "$output_path")"
            : > "$output_path"
        fi
        ;;
    shasum)
        echo "0000000000000000000000000000000000000000000000000000000000000000  ${!#}"
        ;;
esac
MOCK
    chmod +x "$mock_bin/mock-command"

    local command_name
    for command_name in swift security codesign ditto xcrun shasum; do
        ln -s mock-command "$mock_bin/$command_name"
    done

    echo "$fixture_dir"
}

run_packager() {
    local fixture_dir="$1"
    shift

    (
        export PROJECT_ROOT="$fixture_dir"
        export COMMAND_LOG="$fixture_dir/commands.log"
        export PATH="$fixture_dir/mock-bin:/usr/bin:/bin"
        cd "$fixture_dir"
        env "SPARKLE_PUBLIC_ED_KEY=test-public-key" "$@" \
            "$fixture_dir/scripts/package-app.sh" 2.0.0
    )
}

test_package_declares_sparkle() {
    grep -F '.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3")' \
        "$ROOT_DIR/Package.swift" >/dev/null ||
        fail "Package.swift must pin Sparkle 2.9.3"
    grep -F '.product(name: "Sparkle", package: "Sparkle")' \
        "$ROOT_DIR/Package.swift" >/dev/null ||
        fail "ProxyBar target must link the Sparkle product"
    grep -F '@loader_path/../Frameworks' "$ROOT_DIR/Package.swift" >/dev/null ||
        fail "ProxyBar must search the app bundle Frameworks directory"
}

test_app_wires_standard_updater() {
    grep -F 'import Sparkle' "$ROOT_DIR/Sources/ProxyBar/AppDelegate.swift" >/dev/null ||
        fail "AppDelegate must import Sparkle"
    grep -F 'SPUStandardUpdaterController' "$ROOT_DIR/Sources/ProxyBar/AppDelegate.swift" >/dev/null ||
        fail "AppDelegate must own a standard Sparkle updater controller"
    grep -F 'Check for Updates…' "$ROOT_DIR/Sources/ProxyBar/ApplicationMenu.swift" >/dev/null ||
        fail "application menu must expose a manual update command"
    grep -F '#selector(SPUStandardUpdaterController.checkForUpdates(_:))' \
        "$ROOT_DIR/Sources/ProxyBar/ApplicationMenu.swift" >/dev/null ||
        fail "manual update command must call Sparkle"
}

test_readme_documents_sparkle_release() {
    grep -F 'Check for Updates…' "$ROOT_DIR/README.md" >/dev/null ||
        fail "README must document manual update checks"
    grep -F 'SPARKLE_PUBLIC_ED_KEY' "$ROOT_DIR/README.md" >/dev/null ||
        fail "README must document the Sparkle public key"
    grep -F 'generate_keys' "$ROOT_DIR/README.md" >/dev/null ||
        fail "README must document Sparkle key generation"
    grep -F 'appcast.xml' "$ROOT_DIR/README.md" >/dev/null ||
        fail "README must document the appcast release asset"
}

test_default_identity_and_notarization_flow() {
    local fixture_dir
    fixture_dir="$(create_fixture default-flow)"

    run_packager "$fixture_dir" >/dev/null

    local log_path="$fixture_dir/commands.log"
    assert_log_contains "$log_path" \
        "security find-identity -v -p codesigning"
    assert_log_contains "$log_path" \
        "codesign --force --options runtime --timestamp --sign Developer\\ ID\\ Application:\\ Example\\ \\(TEAMID\\)"
    assert_log_contains "$log_path" \
        "codesign --verify --deep --strict --verbose=2"
    assert_log_contains "$log_path" \
        "xcrun notarytool submit"
    assert_log_contains "$log_path" \
        "--keychain-profile develop --wait"
    assert_log_contains "$log_path" \
        "xcrun stapler staple"
    assert_log_contains "$log_path" \
        "xcrun stapler validate"
    assert_log_contains "$log_path" \
        "generate_appcast -o $fixture_dir/dist/appcast.xml --download-url-prefix https://github.com/baha2046/ProxyBar/releases/download/v2.0.0/"
    [[ -f "$fixture_dir/dist/appcast.xml" ]] ||
        fail "expected generated appcast"
    grep -F 'sparkle:edSignature=' "$fixture_dir/dist/appcast.xml" >/dev/null ||
        fail "expected signed appcast enclosure"

    local framework_sign_line
    local app_sign_line
    framework_sign_line="$(
        grep -nF "Sparkle.framework" "$log_path" |
            grep -vF "Versions/B/" |
            grep -F "codesign --force" |
            cut -d: -f1
    )"
    app_sign_line="$(
        grep -nE '^codesign --force .*ProxyBar\.app$' "$log_path" |
            cut -d: -f1
    )"
    [[ "$framework_sign_line" -lt "$app_sign_line" ]] ||
        fail "Sparkle framework must be signed before the outer app"
    assert_log_contains "$log_path" \
        "Downloader.xpc"
    assert_log_contains "$log_path" \
        "--preserve-metadata=entitlements"

    local info_plist="$fixture_dir/.build/ProxyBar.app/Contents/Info.plist"
    /usr/bin/plutil -lint "$info_plist" >/dev/null ||
        fail "generated Info.plist must be valid"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")" == "2.0.0" ]] ||
        fail "bundle version must default to the release version"
    grep -F '<key>SUFeedURL</key>' "$info_plist" >/dev/null ||
        fail "expected Sparkle feed URL"
    grep -F 'https://github.com/baha2046/ProxyBar/releases/latest/download/appcast.xml' \
        "$info_plist" >/dev/null ||
        fail "expected stable GitHub appcast URL"
    grep -F '<key>SUPublicEDKey</key>' "$info_plist" >/dev/null ||
        fail "expected Sparkle public key"
    grep -F '<string>test-public-key</string>' "$info_plist" >/dev/null ||
        fail "expected supplied Sparkle public key"
    grep -F '<key>SUEnableAutomaticChecks</key>' "$info_plist" >/dev/null ||
        fail "expected automatic checks"
    grep -F '<key>SUAutomaticallyUpdate</key>' "$info_plist" >/dev/null ||
        fail "expected automatic updates"
    [[ -f "$fixture_dir/.build/ProxyBar.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" ]] ||
        fail "expected embedded Sparkle framework"

    local validate_line
    local final_zip_line
    validate_line="$(grep -nF "xcrun stapler validate" "$log_path" | cut -d: -f1)"
    final_zip_line="$(
        grep -nE '^ditto .*ProxyBar-2\.0\.0\.zip$' "$log_path" |
            cut -d: -f1
    )"
    [[ "$validate_line" -lt "$final_zip_line" ]] ||
        fail "stapler validation must precede final archive creation"

    [[ -f "$fixture_dir/dist/ProxyBar-2.0.0.zip" ]] ||
        fail "expected final release zip"
}

test_appcast_failure_removes_release_outputs() {
    local fixture_dir
    fixture_dir="$(create_fixture appcast-failure)"

    if run_packager "$fixture_dir" "MOCK_APPCAST_FAILURE=1" >/dev/null 2>&1; then
        fail "expected packaging to fail when appcast generation fails"
    fi

    [[ ! -f "$fixture_dir/dist/ProxyBar-2.0.0.zip" ]] ||
        fail "release zip must be removed after appcast generation failure"
    [[ ! -f "$fixture_dir/dist/appcast.xml" ]] ||
        fail "failed appcast must not remain"
}

test_unsigned_appcast_removes_release_outputs() {
    local fixture_dir
    fixture_dir="$(create_fixture unsigned-appcast)"

    if run_packager "$fixture_dir" "MOCK_APPCAST_UNSIGNED=1" >/dev/null 2>&1; then
        fail "expected packaging to fail when the appcast has no EdDSA signature"
    fi

    [[ ! -f "$fixture_dir/dist/ProxyBar-2.0.0.zip" ]] ||
        fail "release zip must be removed after unsigned appcast generation"
    [[ ! -f "$fixture_dir/dist/appcast.xml" ]] ||
        fail "unsigned appcast must not remain"
}

test_missing_sparkle_public_key_stops_before_build() {
    local fixture_dir
    fixture_dir="$(create_fixture missing-sparkle-key)"

    if run_packager "$fixture_dir" "SPARKLE_PUBLIC_ED_KEY=" >/dev/null 2>&1; then
        fail "expected packaging to fail without SPARKLE_PUBLIC_ED_KEY"
    fi

    assert_log_excludes "$fixture_dir/commands.log" "swift build"
    [[ ! -f "$fixture_dir/dist/ProxyBar-2.0.0.zip" ]] ||
        fail "final release zip must not exist without Sparkle public key"
}

test_signing_identity_override_bypasses_discovery() {
    local fixture_dir
    fixture_dir="$(create_fixture identity-override)"

    run_packager "$fixture_dir" \
        "SIGNING_IDENTITY=Developer ID Application: Override (OVERRIDE)" \
        "NOTARY_PROFILE=custom-profile" \
        "BUILD_NUMBER=42" >/dev/null

    local log_path="$fixture_dir/commands.log"
    assert_log_excludes "$log_path" "security find-identity"
    assert_log_contains "$log_path" \
        "--sign Developer\\ ID\\ Application:\\ Override\\ \\(OVERRIDE\\)"
    assert_log_contains "$log_path" \
        "--keychain-profile custom-profile --wait"
    [[ "$(
        /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
            "$fixture_dir/.build/ProxyBar.app/Contents/Info.plist"
    )" == "42" ]] ||
        fail "BUILD_NUMBER must override the bundle version"
}

test_missing_identity_stops_before_final_archive() {
    local fixture_dir
    fixture_dir="$(create_fixture missing-identity)"

    if run_packager "$fixture_dir" "MOCK_SECURITY_EMPTY=1" >/dev/null 2>&1; then
        fail "expected packaging to fail when no Developer ID identity exists"
    fi

    [[ ! -f "$fixture_dir/dist/ProxyBar-2.0.0.zip" ]] ||
        fail "final release zip must not exist after identity discovery failure"
    assert_log_excludes "$fixture_dir/commands.log" "xcrun notarytool submit"
}

test_package_declares_sparkle
test_app_wires_standard_updater
test_readme_documents_sparkle_release
test_default_identity_and_notarization_flow
test_appcast_failure_removes_release_outputs
test_unsigned_appcast_removes_release_outputs
test_missing_sparkle_public_key_stops_before_build
test_signing_identity_override_bypasses_discovery
test_missing_identity_stops_before_final_archive

echo "package-app tests passed"
