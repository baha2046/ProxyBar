# Sparkle Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Sparkle 2 in-app auto-update (automatic background checks + a manual "Check for Updates…" menu item) to ProxyBar, delivered via an EdDSA-signed appcast on GitHub Pages, with Developer ID signing + notarization of each release.

**Architecture:** ProxyBar is an AppKit menu-bar agent built with **pure SwiftPM** (no `.xcodeproj`). The `.app` bundle is hand-assembled by `scripts/package-app.sh` and its `Info.plist` is generated inline. Sparkle is added as an SPM dependency; the runtime `Sparkle.framework` is embedded into the bundle and signed inside-out with a Developer ID identity, then notarized + stapled. The appcast feed (`appcast.xml`) is hosted on GitHub Pages and points enclosures at GitHub Release zip assets.

**Tech Stack:** Swift 6, AppKit, SwiftPM, Sparkle 2.x, `codesign`/`notarytool`/`stapler`, GitHub Releases + GitHub Pages, Homebrew Cask.

**Prerequisite (in progress):** Apple Developer Program membership + a "Developer ID Application" certificate and a `notarytool` keychain profile. Phases 4–8 (signing/notarization/appcast/release) are **blocked** until the certificate is available. **Phases 1–3 (this pass) do not require the certificate** and can be done now.

---

## Phase 1 — Add Sparkle SPM dependency

**Files:**
- Modify: `Package.swift`

Sparkle is distributed via SPM as a **binary artifact bundle** (xcframework + CLI tools). After `swift build`, it lands under `.build/artifacts/sparkle/Sparkle/` and contains `Sparkle.framework` (embed in Phase 4) and `bin/` with `generate_keys`, `sign_update`, `generate_appcast` (used in Phases 3 & 6).

- [ ] **Step 1: Add the package dependency + product**

In `Package.swift`, add a `dependencies:` array to the `Package(...)` and the product dependency to the `ProxyBar` executable target:

```swift
let package = Package(
    name: "ProxyBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ProxyBar", targets: ["ProxyBar"]),
        .library(name: "ProxyBarCore", targets: ["ProxyBarCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(name: "ProxyBarCore"),
        .executableTarget(
            name: "ProxyBar",
            dependencies: [
                "ProxyBarCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "ProxyBarCoreTests",
            dependencies: ["ProxyBarCore"],
            path: "Tests/ProxyBarCoreTests"
        ),
        .executableTarget(
            name: "IconGenerator",
            path: "Tools/IconGenerator"
        )
    ]
)
```

- [ ] **Step 2: Resolve + fetch the dependency**

Run: `swift package resolve`
Expected: Sparkle is resolved; `Package.resolved` is created/updated with a `sparkle-project/Sparkle` pin.

- [ ] **Step 3: Build to download the binary artifact**

Run: `swift build -c release --product ProxyBar`
Expected: PASS (compiles, downloads Sparkle artifact bundle to `.build/artifacts/sparkle/`).

- [ ] **Step 4: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build: add Sparkle 2 SPM dependency"
```

---

## Phase 2 — Wire Sparkle into the app (Swift)

**Files:**
- Modify: `Sources/ProxyBar/AppDelegate.swift`
- Modify: `Sources/ProxyBar/ApplicationMenu.swift`

`SPUStandardUpdaterController` is the batteries-included controller: it owns the `SPUUpdater`, starts it, and provides the standard update UI. Created with `startingUpdater: true`, it begins background scheduling automatically (gated by `SUEnableAutomaticChecks`, added in Phase 3).

- [ ] **Step 1: Add the updater controller + action to AppDelegate**

In `Sources/ProxyBar/AppDelegate.swift`, add `import Sparkle` at the top, a stored property alongside the other `private let` properties, and an action method.

Add import (after `import ProxyBarCore`):

```swift
import Sparkle
```

Add property (with the other stored properties near the top of `AppDelegate`):

```swift
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
```

Add action method (anywhere among the `@objc` methods, e.g. near `openSettings`):

```swift
    @objc func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }
```

- [ ] **Step 2: Add the menu item**

In `Sources/ProxyBar/ApplicationMenu.swift`, add a "Check for Updates…" item to `appMenu`. Because this is an agent app, target the AppDelegate explicitly rather than relying on the responder chain. Replace the `appMenu` block:

```swift
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let updatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updatesItem.target = NSApp.delegate
        appMenu.addItem(updatesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit ProxyBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
```

> Note: `ApplicationMenu.install()` runs in `applicationDidFinishLaunching`, after `NSApp.delegate` is set, so `NSApp.delegate` is non-nil here.

- [ ] **Step 3: Build**

Run: `swift build -c release --product ProxyBar`
Expected: PASS.

- [ ] **Step 4: Smoke-test the menu wiring (manual)**

Run: `swift run -c release ProxyBar` (or build+launch the packaged app once Phase 3 plist exists). With no `SUFeedURL` yet, "Check for Updates…" will error about a missing feed — that's expected until Phase 3. The goal here is only to confirm the menu item exists and is enabled.

- [ ] **Step 5: Commit**

```bash
git add Sources/ProxyBar/AppDelegate.swift Sources/ProxyBar/ApplicationMenu.swift
git commit -m "feat: wire Sparkle updater controller and Check for Updates menu item"
```

---

## Phase 3 — EdDSA keys + Sparkle Info.plist config

**Files:**
- Modify: `scripts/package-app.sh` (Info.plist heredoc)
- Create: `docs/superpowers/specs/sparkle-keys.md` (records the public key + key-custody notes; private key never committed)

Sparkle verifies update archives with an Ed25519 (EdDSA) signature. `generate_keys` creates the keypair, stores the **private** key in the login Keychain, and prints the **public** key, which goes into `Info.plist` as `SUPublicEDKey`.

- [ ] **Step 1: Generate the EdDSA keypair (one-time)**

Locate the tool in the resolved artifact bundle and run it:

```bash
SPARKLE_BIN="$(find .build/artifacts -type d -name bin -path '*Sparkle*' | head -n1)"
"$SPARKLE_BIN/generate_keys"
```

Expected: prints "A key has been generated and saved in your keychain." and a public key like `SUPublicEDKey ...` (a base64 string). If a key already exists it prints the existing public key. Copy the public key string.

> Custody: the private key lives only in the macOS login Keychain (item "Private key for signing Sparkle updates"). Do NOT commit it. For CI, export with `generate_keys -x private-key-file` and store as a CI secret; never check it in.

- [ ] **Step 2: Record the public key**

Create `docs/superpowers/specs/sparkle-keys.md`:

```markdown
# Sparkle Update Signing Keys

- **Public EdDSA key (SUPublicEDKey):** `<PASTE_PUBLIC_KEY_HERE>`
- **Private key location:** macOS login Keychain, item "Private key for signing Sparkle updates" (do NOT commit).
- **CI:** export via `generate_keys -x private-key.pem`, store as secret `SPARKLE_PRIVATE_KEY`, import with `generate_keys -f private-key.pem` (or pass to `sign_update` / `generate_appcast --ed-key-file`).
- **Feed URL:** https://baha2046.github.io/ProxyBar/appcast.xml
```

- [ ] **Step 3: Add Sparkle keys to the generated Info.plist**

In `scripts/package-app.sh`, inside the Info.plist heredoc (currently lines 23–48), add the Sparkle keys before the closing `</dict>`:

```xml
    <key>SUFeedURL</key>
    <string>https://baha2046.github.io/ProxyBar/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>$SU_PUBLIC_ED_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
```

And near the top of the script (with the other variable defaults, around line 7), add:

```bash
SU_PUBLIC_ED_KEY="${SU_PUBLIC_ED_KEY:-<PASTE_PUBLIC_KEY_HERE>}"
```

> The default literal is the public key (public keys are safe to commit). The env var allows overriding without editing the script.

- [ ] **Step 4: Verify the plist renders correctly**

Run: `SU_PUBLIC_ED_KEY=test ./scripts/package-app.sh 1.0.2 || true` then inspect:
Run: `/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' .build/ProxyBar.app/Contents/Info.plist`
Expected: `https://baha2046.github.io/ProxyBar/appcast.xml`
Run: `/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' .build/ProxyBar.app/Contents/Info.plist`
Expected: `test`

> Note: this packaging run will still ad-hoc sign (no Developer ID yet) and will NOT embed Sparkle.framework — that is Phase 4. The app won't fully run updates yet; this step only validates plist generation.

- [ ] **Step 5: Commit**

```bash
git add scripts/package-app.sh docs/superpowers/specs/sparkle-keys.md
git commit -m "feat: add Sparkle feed + public key to generated Info.plist"
```

---

## Phase 4 — Embed + Developer-ID-sign Sparkle.framework (BLOCKED on certificate)

**Files:**
- Modify: `scripts/package-app.sh`
- Create: `scripts/ProxyBar.entitlements`

- [ ] **Step 1: Add a hardened-runtime entitlements file**

Create `scripts/ProxyBar.entitlements` (non-sandboxed app; start minimal, add `com.apple.security.cs.disable-library-validation` only if notarization/library-validation fails):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- [ ] **Step 2: Locate and embed Sparkle.framework**

In `scripts/package-app.sh`, after the binary is copied (after line 20) and before signing, add:

```bash
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts" -type d -name 'Sparkle.framework' -path '*macos-arm64_x86_64*' | head -n1)"
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts" -type d -name 'Sparkle.framework' | head -n1)"
fi
[ -n "$SPARKLE_FRAMEWORK" ] || { echo "Sparkle.framework not found; run swift build first" >&2; exit 1; }
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
```

- [ ] **Step 3: Replace ad-hoc signing with inside-out Developer ID signing**

Replace line 50 (`/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"`) with:

```bash
SIGN_FLAGS=(--force --options runtime --timestamp --sign "$SIGNING_IDENTITY")
SPARKLE_VERS="$FRAMEWORKS_DIR/Sparkle.framework/Versions/B"
/usr/bin/codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERS/XPCServices/Installer.xpc"
/usr/bin/codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERS/XPCServices/Downloader.xpc"
/usr/bin/codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERS/Autoupdate"
/usr/bin/codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERS/Updater.app"
/usr/bin/codesign "${SIGN_FLAGS[@]}" "$FRAMEWORKS_DIR/Sparkle.framework"
/usr/bin/codesign "${SIGN_FLAGS[@]}" "$MACOS_DIR/ProxyBar"
/usr/bin/codesign "${SIGN_FLAGS[@]}" --entitlements "$ROOT_DIR/scripts/ProxyBar.entitlements" "$APP_DIR"
```

Also make the script fail fast if `SIGNING_IDENTITY` is still ad-hoc:

```bash
if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "Refusing to ad-hoc sign: set SIGNING_IDENTITY to a 'Developer ID Application' identity" >&2
    exit 1
fi
```

> Skip the fail-fast guard while still waiting on the certificate by running with an explicit identity once available.

- [ ] **Step 4: Verify signing**

Run: `codesign --verify --deep --strict --verbose=2 .build/ProxyBar.app`
Expected: `valid on disk` / `satisfies its Designated Requirement`.

- [ ] **Step 5: Commit**

```bash
git add scripts/package-app.sh scripts/ProxyBar.entitlements
git commit -m "build: embed and Developer-ID-sign Sparkle.framework"
```

---

## Phase 5 — Notarization + stapling (BLOCKED on certificate)

**Files:**
- Create: `scripts/notarize.sh`

- [ ] **Step 1: Create the notarize script**

Create `scripts/notarize.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?usage: notarize.sh <version>}"
PROFILE="${NOTARY_PROFILE:?set NOTARY_PROFILE to your notarytool keychain profile}"
APP_DIR="$ROOT_DIR/.build/ProxyBar.app"
ZIP_PATH="$ROOT_DIR/dist/ProxyBar-$VERSION.zip"

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP_DIR"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"
xcrun stapler validate "$APP_DIR"
spctl -a -vvv -t install "$APP_DIR"
echo "Notarized + stapled. Final zip: $ZIP_PATH"
/usr/bin/shasum -a 256 "$ZIP_PATH"
```

- [ ] **Step 2: Make executable + commit**

```bash
chmod +x scripts/notarize.sh
git add scripts/notarize.sh
git commit -m "build: add notarization + stapling script"
```

---

## Phase 6 — Appcast generation + GitHub Pages (BLOCKED on certificate)

**Files:**
- Create: `scripts/make-appcast.sh`

- [ ] **Step 1: Create the appcast generation script**

Create `scripts/make-appcast.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DL_PREFIX="${DL_PREFIX:-https://github.com/baha2046/ProxyBar/releases/download}"
SPARKLE_BIN="$(find "$ROOT_DIR/.build/artifacts" -type d -name bin -path '*Sparkle*' | head -n1)"
[ -n "$SPARKLE_BIN" ] || { echo "Sparkle bin not found; run swift build" >&2; exit 1; }
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "$DL_PREFIX/" "$DIST_DIR"
echo "Wrote $DIST_DIR/appcast.xml"
```

> `generate_appcast` reads the private EdDSA key from Keychain, scans the zips in `dist/`, and writes `appcast.xml` with `sparkle:edSignature`/`length`/version metadata. Each enclosure URL is `<DL_PREFIX>/v<version>/ProxyBar-<version>.zip`; ensure the release tag/asset names match.

- [ ] **Step 2: Set up GitHub Pages hosting**

In the `baha2046/ProxyBar` repo, enable GitHub Pages (e.g. a `gh-pages` branch or `/docs` source) serving `appcast.xml` at `https://baha2046.github.io/ProxyBar/appcast.xml` (must equal `SUFeedURL`). On each release, copy `dist/appcast.xml` to the Pages source and push.

- [ ] **Step 3: Make executable + commit**

```bash
chmod +x scripts/make-appcast.sh
git add scripts/make-appcast.sh
git commit -m "build: add appcast generation script"
```

---

## Phase 7 — Release flow + docs (BLOCKED on certificate)

**Files:**
- Modify: `docs/superpowers/plans/2026-06-19-1.0-github-brew-cask-release.md`
- Modify: `README.md`
- Modify (separate tap repo): `Casks/proxybar.rb`

- [ ] **Step 1: Update the release runbook** to: `package-app.sh` (build/embed/sign) → `notarize.sh` (notarize/staple) → `gh release create` upload zip → `make-appcast.sh` → push `appcast.xml` to Pages.
- [ ] **Step 2: README** — document auto-update; remove the `xattr -dr com.apple.quarantine` workaround note for notarized builds.
- [ ] **Step 3: Homebrew cask** — set `auto_updates true` in `Casks/proxybar.rb` so `brew upgrade` doesn't fight Sparkle's in-place update.
- [ ] **Step 4: Commit** docs changes.

---

## Phase 8 — End-to-end verification (BLOCKED on certificate)

- [ ] `swift build -c release` passes with Sparkle linked.
- [ ] Packaged app contains `Contents/Frameworks/Sparkle.framework`; `codesign --verify --deep --strict` passes; `spctl -a -vvv -t install` accepts; `stapler validate` passes.
- [ ] Functional update test: install an older notarized build (e.g. 1.0.1) in `/Applications`, publish a newer appcast entry (e.g. 1.0.2), launch, confirm Sparkle detects → downloads → verifies (EdDSA) → installs → relaunches.
- [ ] Manual "Check for Updates…" menu item works.
- [ ] App still launches as a menu-bar agent; proxy functionality unaffected.

---

## Risks / notes

1. **Developer ID required** for Phases 4–8: a "Developer ID Application" cert + `notarytool` keychain profile. Ad-hoc signed updates are Gatekeeper-blocked on end-user Macs.
2. **Inside-out signing order** is the most error-prone step; Phase 8's `codesign`/`spctl`/`stapler` checks are the guardrails. Sparkle's `Versions/B` symlink layout must be preserved (use `ditto`, not `cp -R` without `-R`).
3. **Private EdDSA key custody:** Keychain locally; CI secret otherwise. Losing it breaks updates for existing installs.
4. **Homebrew vs Sparkle:** mitigated with `auto_updates true`.