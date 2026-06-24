# Sparkle Automatic Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add secure Sparkle 2.9.3 background update checks, automatic downloads, a manual update command, and an EdDSA-signed GitHub Releases appcast to ProxyBar.

**Architecture:** Link the official Sparkle Swift package into the AppKit executable and keep one `SPUStandardUpdaterController` alive in `AppDelegate`. Extend the existing shell packaging pipeline to embed and sign Sparkle's framework and helper services, inject update configuration into `Info.plist`, and generate an appcast from the notarized ZIP. Keep release behavior covered by the existing command-mocking shell test harness.

**Tech Stack:** Swift 6, AppKit, Swift Package Manager, Sparkle 2.9.3, Bash, Developer ID signing, Apple notarization, GitHub Releases

---

## File Structure

- `Package.swift`: declare Sparkle 2.9.3 and link its `Sparkle` product to the app.
- `Sources/ProxyBar/AppDelegate.swift`: own and start the standard updater controller.
- `Sources/ProxyBar/ApplicationMenu.swift`: install the manual update menu item.
- `scripts/package-app.sh`: validate update configuration, embed/sign Sparkle, write update keys, and generate the appcast.
- `Tests/PackageAppTests/package-app-tests.sh`: exercise package metadata and release behavior with deterministic mocks.
- `README.md`: document end-user behavior and release-key/appcast workflow.

### Task 1: Declare and Link Sparkle

**Files:**
- Modify: `Package.swift`
- Modify: `Tests/PackageAppTests/package-app-tests.sh`

- [ ] **Step 1: Add a failing package-manifest test**

Add a test that reads `Package.swift` and requires both the pinned package and
the executable product dependency:

```bash
test_package_declares_sparkle() {
    grep -F '.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3")' \
        "$ROOT_DIR/Package.swift" >/dev/null ||
        fail "Package.swift must pin Sparkle 2.9.3"
    grep -F '.product(name: "Sparkle", package: "Sparkle")' \
        "$ROOT_DIR/Package.swift" >/dev/null ||
        fail "ProxyBar target must link the Sparkle product"
}
```

Call it before the packaging behavior tests.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
Tests/PackageAppTests/package-app-tests.sh
```

Expected: failure containing `Package.swift must pin Sparkle 2.9.3`.

- [ ] **Step 3: Add the Sparkle package and product**

Update the package declaration:

```swift
dependencies: [
    .package(
        url: "https://github.com/sparkle-project/Sparkle",
        exact: "2.9.3"
    )
],
```

Update the executable target dependencies:

```swift
dependencies: [
    "ProxyBarCore",
    .product(name: "Sparkle", package: "Sparkle")
]
```

- [ ] **Step 4: Run the package test and resolve/build**

Run:

```bash
Tests/PackageAppTests/package-app-tests.sh
swift package resolve
swift build --product ProxyBar
```

Expected: shell tests pass, dependency resolution selects Sparkle 2.9.3, and
the debug executable builds.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved Tests/PackageAppTests/package-app-tests.sh
git commit -m "build: add Sparkle update framework"
```

### Task 2: Start Sparkle and Add the Manual Menu Command

**Files:**
- Modify: `Sources/ProxyBar/AppDelegate.swift`
- Modify: `Sources/ProxyBar/ApplicationMenu.swift`
- Modify: `Tests/PackageAppTests/package-app-tests.sh`

- [ ] **Step 1: Add failing source-wiring tests**

Add:

```bash
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
```

Call it from the test runner.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
Tests/PackageAppTests/package-app-tests.sh
```

Expected: failure containing `AppDelegate must import Sparkle`.

- [ ] **Step 3: Own the updater controller**

In `AppDelegate.swift`, import Sparkle and add:

```swift
private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
```

Pass it while installing the menu:

```swift
ApplicationMenu.install(updaterController: updaterController)
```

- [ ] **Step 4: Add the menu item**

Import Sparkle in `ApplicationMenu.swift`, change the signature to:

```swift
static func install(updaterController: SPUStandardUpdaterController)
```

Before the Quit item, add:

```swift
let checkForUpdatesItem = NSMenuItem(
    title: "Check for Updates…",
    action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
    keyEquivalent: ""
)
checkForUpdatesItem.target = updaterController
appMenu.addItem(checkForUpdatesItem)
appMenu.addItem(.separator())
```

- [ ] **Step 5: Run tests and build**

Run:

```bash
Tests/PackageAppTests/package-app-tests.sh
swift build --product ProxyBar
```

Expected: source-wiring tests pass and the app builds.

- [ ] **Step 6: Commit**

```bash
git add Sources/ProxyBar/AppDelegate.swift Sources/ProxyBar/ApplicationMenu.swift Tests/PackageAppTests/package-app-tests.sh
git commit -m "feat: add Sparkle update controls"
```

### Task 3: Embed and Configure Sparkle During Packaging

**Files:**
- Modify: `scripts/package-app.sh`
- Modify: `Tests/PackageAppTests/package-app-tests.sh`

- [ ] **Step 1: Extend the fixture to model Sparkle artifacts**

In `create_fixture`, create:

```bash
local sparkle_framework="$fixture_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$sparkle_framework/Versions/B/Resources"
: > "$sparkle_framework/Versions/B/Sparkle"
ln -s B "$sparkle_framework/Versions/Current"
ln -s Versions/Current/Sparkle "$sparkle_framework/Sparkle"
ln -s Versions/Current/Resources "$sparkle_framework/Resources"
```

Teach the `swift build` mock to preserve this artifact and teach the `ditto`
mock to copy directories when invoked without archive flags:

```bash
if [[ -d "${1:-}" && "$*" != *" -c "* ]]; then
    cp -R "$1" "$2"
else
    output_path="${!#}"
    mkdir -p "$(dirname "$output_path")"
    : > "$output_path"
fi
```

- [ ] **Step 2: Add failing configuration and embedding assertions**

Update `run_packager` to supply:

```bash
"SPARKLE_PUBLIC_ED_KEY=test-public-key"
```

In the default-flow test assert:

```bash
grep -F '<key>SUFeedURL</key>' "$fixture_dir/.build/ProxyBar.app/Contents/Info.plist" >/dev/null ||
    fail "expected Sparkle feed URL"
grep -F 'https://github.com/baha2046/ProxyBar/releases/latest/download/appcast.xml' \
    "$fixture_dir/.build/ProxyBar.app/Contents/Info.plist" >/dev/null ||
    fail "expected stable GitHub appcast URL"
grep -F '<key>SUPublicEDKey</key>' "$fixture_dir/.build/ProxyBar.app/Contents/Info.plist" >/dev/null ||
    fail "expected Sparkle public key"
grep -F '<key>SUEnableAutomaticChecks</key>' "$fixture_dir/.build/ProxyBar.app/Contents/Info.plist" >/dev/null ||
    fail "expected automatic checks"
grep -F '<key>SUAutomaticallyUpdate</key>' "$fixture_dir/.build/ProxyBar.app/Contents/Info.plist" >/dev/null ||
    fail "expected automatic updates"
[[ -f "$fixture_dir/.build/ProxyBar.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" ]] ||
    fail "expected embedded Sparkle framework"
```

Add a test invoking the packager without `SPARKLE_PUBLIC_ED_KEY` and require
failure before `swift build`.

- [ ] **Step 3: Run the tests and verify RED**

Run:

```bash
Tests/PackageAppTests/package-app-tests.sh
```

Expected: failure because the current script ignores
`SPARKLE_PUBLIC_ED_KEY` and does not embed the framework.

- [ ] **Step 4: Validate release inputs and locate Sparkle**

At the top of `package-app.sh`, add:

```bash
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/baha2046/ProxyBar/releases/latest/download/appcast.xml}"
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"

if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "SPARKLE_PUBLIC_ED_KEY is required for Sparkle updates." >&2
    exit 1
fi
```

After building, locate the single framework:

```bash
SPARKLE_FRAMEWORK="$(
    find "$ROOT_DIR/.build/artifacts" -path '*/Sparkle.framework' -type d -print -quit
)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework was not found under .build/artifacts." >&2
    exit 1
fi
```

- [ ] **Step 5: Embed the framework and configure the bundle**

Create `Contents/Frameworks`, copy with symlinks preserved:

```bash
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$DIST_DIR"
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
```

Add these keys to the generated plist:

```xml
<key>SUFeedURL</key>
<string>$SPARKLE_FEED_URL</string>
<key>SUPublicEDKey</key>
<string>$SPARKLE_PUBLIC_ED_KEY</string>
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUAutomaticallyUpdate</key>
<true/>
```

- [ ] **Step 6: Sign Sparkle before signing the app**

Before the outer-app signing command, sign Sparkle's nested XPC services,
Autoupdate helper, and framework:

```bash
while IFS= read -r component; do
    /usr/bin/codesign --force --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" "$component"
done < <(
    find "$FRAMEWORKS_DIR/Sparkle.framework" \
        \( -name '*.xpc' -o -name 'Autoupdate' \) -print
)

/usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework"
```

Keep the existing hardened-runtime app signing and final verification after
these nested signatures.

- [ ] **Step 7: Run packaging tests and inspect a real build**

Run:

```bash
Tests/PackageAppTests/package-app-tests.sh
SPARKLE_PUBLIC_ED_KEY=test-public-key swift build -c release --product ProxyBar
otool -L .build/release/ProxyBar | grep Sparkle
otool -l .build/release/ProxyBar | grep -A2 LC_RPATH
```

Expected: tests pass; `otool -L` lists `@rpath/Sparkle.framework/...`; the
executable contains an rpath resolving `Contents/Frameworks`.

- [ ] **Step 8: Commit**

```bash
git add scripts/package-app.sh Tests/PackageAppTests/package-app-tests.sh
git commit -m "build: embed and configure Sparkle"
```

### Task 4: Generate a Signed GitHub Releases Appcast

**Files:**
- Modify: `scripts/package-app.sh`
- Modify: `Tests/PackageAppTests/package-app-tests.sh`

- [ ] **Step 1: Add a mocked appcast generator**

Extend the fixture with:

```bash
local sparkle_tools="$fixture_dir/sparkle-tools"
mkdir -p "$sparkle_tools"
cat > "$sparkle_tools/generate_appcast" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'generate_appcast' >> "$COMMAND_LOG"
printf ' %q' "$@" >> "$COMMAND_LOG"
printf '\n' >> "$COMMAND_LOG"
output_path=""
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
        output_path="$2"
        shift 2
    else
        shift
    fi
done
cat > "$output_path" <<'XML'
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><item><enclosure sparkle:edSignature="test-signature"/></item></channel>
</rss>
XML
MOCK
chmod +x "$sparkle_tools/generate_appcast"
```

Have `run_packager` export:

```bash
"SPARKLE_GENERATE_APPCAST=$fixture_dir/sparkle-tools/generate_appcast"
```

- [ ] **Step 2: Add failing appcast assertions**

Require:

```bash
assert_log_contains "$log_path" \
    "generate_appcast -o $fixture_dir/dist/appcast.xml --download-url-prefix https://github.com/baha2046/ProxyBar/releases/download/v2.0.0/"
[[ -f "$fixture_dir/dist/appcast.xml" ]] ||
    fail "expected generated appcast"
grep -F 'sparkle:edSignature=' "$fixture_dir/dist/appcast.xml" >/dev/null ||
    fail "expected signed appcast enclosure"
```

Add a fixture option where `generate_appcast` exits non-zero and assert no
successful completion message is emitted.

- [ ] **Step 3: Run the tests and verify RED**

Run:

```bash
Tests/PackageAppTests/package-app-tests.sh
```

Expected: failure containing `expected command log to contain:
generate_appcast`.

- [ ] **Step 4: Validate and run `generate_appcast`**

Add the release input:

```bash
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"

if [[ -z "$SPARKLE_GENERATE_APPCAST" || ! -x "$SPARKLE_GENERATE_APPCAST" ]]; then
    echo "SPARKLE_GENERATE_APPCAST must point to Sparkle's executable generate_appcast tool." >&2
    exit 1
fi
```

After creating the final ZIP:

```bash
"$SPARKLE_GENERATE_APPCAST" \
    -o "$DIST_DIR/appcast.xml" \
    --download-url-prefix "https://github.com/baha2046/ProxyBar/releases/download/v$VERSION/" \
    "$DIST_DIR"

if ! grep -F 'sparkle:edSignature=' "$DIST_DIR/appcast.xml" >/dev/null; then
    echo "Generated appcast does not contain an EdDSA update signature." >&2
    exit 1
fi
```

Remove any prior `dist/appcast.xml` at startup so failures cannot leave a stale
feed behind.

- [ ] **Step 5: Run tests**

Run:

```bash
bash -n scripts/package-app.sh
Tests/PackageAppTests/package-app-tests.sh
```

Expected: syntax validation and all packaging tests pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/package-app.sh Tests/PackageAppTests/package-app-tests.sh
git commit -m "build: generate signed Sparkle appcast"
```

### Task 5: Document Update and Release Operations

**Files:**
- Modify: `README.md`
- Modify: `Tests/PackageAppTests/package-app-tests.sh`

- [ ] **Step 1: Add failing documentation assertions**

Add:

```bash
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
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
Tests/PackageAppTests/package-app-tests.sh
```

Expected: failure containing `README must document manual update checks`.

- [ ] **Step 3: Update README**

Document that ProxyBar checks daily, downloads updates automatically, installs
on quit where possible, and exposes `Check for Updates…`.

Add a release section with:

```bash
/path/to/Sparkle-2.9.3/bin/generate_keys
export SPARKLE_PUBLIC_ED_KEY='<public key printed by generate_keys>'
export SPARKLE_GENERATE_APPCAST='/path/to/Sparkle-2.9.3/bin/generate_appcast'
scripts/package-app.sh 1.0.3
```

Explain that `Sparkle-2.9.3.tar.xz` is the full official Sparkle distribution,
while SwiftPM's separate ZIP supplies the linked framework. State that the
private key stays in Keychain and that both
`dist/ProxyBar-1.0.3.zip` and `dist/appcast.xml` must be uploaded to the GitHub
release tagged `v1.0.3`.

- [ ] **Step 4: Run documentation and full tests**

Run:

```bash
Tests/PackageAppTests/package-app-tests.sh
swift run ProxyBarCoreTests
swift build --product ProxyBar
```

Expected: all commands exit successfully.

- [ ] **Step 5: Commit**

```bash
git add README.md Tests/PackageAppTests/package-app-tests.sh
git commit -m "docs: explain Sparkle update releases"
```

### Task 6: Final Verification

**Files:**
- Verify: all modified files

- [ ] **Step 1: Verify repository state and formatting**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intentional files are modified or the
worktree is clean after task commits.

- [ ] **Step 2: Run the complete automated suite**

Run:

```bash
bash -n scripts/package-app.sh
Tests/PackageAppTests/package-app-tests.sh
swift run ProxyBarCoreTests
swift build -c release --product ProxyBar
```

Expected: all commands exit zero.

- [ ] **Step 3: Verify binary linkage**

Run:

```bash
otool -L .build/release/ProxyBar | grep 'Sparkle.framework'
otool -l .build/release/ProxyBar | grep -A2 LC_RPATH
```

Expected: the binary links Sparkle through `@rpath` and includes the framework
runtime search path used by the app bundle.

- [ ] **Step 4: Review requirements**

Confirm from the diff and test output that the implementation includes:

- daily scheduled background checks;
- automatic download/install-on-quit behavior;
- manual update menu command;
- stable GitHub appcast feed;
- public EdDSA key configuration;
- embedded and nested-signed Sparkle components;
- signed appcast generation;
- monotonic bundle-version handling;
- release documentation.

- [ ] **Step 5: Commit any final corrections**

If final verification required a correction, rerun Steps 1–4 and commit only
after every command passes.
