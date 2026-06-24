#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/package-app.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/proxybar-package-tests.XXXXXX")"

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
    grep -F -- "$expected" "$log_path" >/dev/null ||
        fail "expected command log to contain: $expected"
}

assert_log_excludes() {
    local log_path="$1"
    local unexpected="$2"
    if grep -F -- "$unexpected" "$log_path" >/dev/null; then
        fail "expected command log not to contain: $unexpected"
    fi
}

create_fixture() {
    local name="$1"
    local fixture_dir="$TEST_ROOT/$name"
    local mock_bin="$fixture_dir/mock-bin"

    mkdir -p "$fixture_dir/scripts" "$mock_bin"
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
        output_path="${!#}"
        mkdir -p "$(dirname "$output_path")"
        : > "$output_path"
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
        env "$@" "$fixture_dir/scripts/package-app.sh" 2.0.0
    )
}

test_default_identity_and_notarization_flow() {
    local fixture_dir
    fixture_dir="$(create_fixture default-flow)"

    run_packager "$fixture_dir" >/dev/null

    local log_path="$fixture_dir/commands.log"
    assert_log_contains "$log_path" \
        "security find-identity -v -p codesigning"
    assert_log_contains "$log_path" \
        "codesign --force --deep --options runtime --timestamp --sign Developer\\ ID\\ Application:\\ Example\\ \\(TEAMID\\)"
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

test_signing_identity_override_bypasses_discovery() {
    local fixture_dir
    fixture_dir="$(create_fixture identity-override)"

    run_packager "$fixture_dir" \
        "SIGNING_IDENTITY=Developer ID Application: Override (OVERRIDE)" \
        "NOTARY_PROFILE=custom-profile" >/dev/null

    local log_path="$fixture_dir/commands.log"
    assert_log_excludes "$log_path" "security find-identity"
    assert_log_contains "$log_path" \
        "--sign Developer\\ ID\\ Application:\\ Override\\ \\(OVERRIDE\\)"
    assert_log_contains "$log_path" \
        "--keychain-profile custom-profile --wait"
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

test_default_identity_and_notarization_flow
test_signing_identity_override_bypasses_discovery
test_missing_identity_stops_before_final_archive

echo "package-app tests passed"
