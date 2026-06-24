# Settings Update Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the manual Sparkle update action from the application menu to a right-aligned button beside the version label in Settings.

**Architecture:** Keep the Settings UI independent of Sparkle by forwarding an `onCheckForUpdates` closure through `SettingsWindowController`. `AppDelegate` remains the owner of `SPUStandardUpdaterController` and invokes its update check when the Settings button calls back.

**Tech Stack:** Swift 6, AppKit, Sparkle 2.9.3, Bash source-wiring tests

---

## File Structure

- `Sources/ProxyBar/SettingsWindowController.swift`: add the footer button and callback forwarding.
- `Sources/ProxyBar/AppDelegate.swift`: connect the Settings callback to the existing updater controller.
- `Sources/ProxyBar/ApplicationMenu.swift`: remove the update menu item and Sparkle dependency.
- `Tests/PackageAppTests/package-app-tests.sh`: verify placement and callback wiring.

### Task 1: Move the Manual Update Action

**Files:**
- Modify: `Tests/PackageAppTests/package-app-tests.sh`
- Modify: `Sources/ProxyBar/SettingsWindowController.swift`
- Modify: `Sources/ProxyBar/AppDelegate.swift`
- Modify: `Sources/ProxyBar/ApplicationMenu.swift`

- [ ] **Step 1: Write the failing placement test**

Replace the existing update-wiring assertions with:

```bash
test_app_wires_standard_updater() {
    grep -F 'SPUStandardUpdaterController' "$ROOT_DIR/Sources/ProxyBar/AppDelegate.swift" >/dev/null ||
        fail "AppDelegate must own a standard Sparkle updater controller"
    grep -F 'onCheckForUpdates' "$ROOT_DIR/Sources/ProxyBar/AppDelegate.swift" >/dev/null ||
        fail "AppDelegate must connect the Settings update callback"
    grep -F '#selector(SPUStandardUpdaterController.checkForUpdates(_:))' \
        "$ROOT_DIR/Sources/ProxyBar/AppDelegate.swift" >/dev/null ||
        fail "Settings callback must invoke Sparkle"
    grep -F 'Check for Updates…' "$ROOT_DIR/Sources/ProxyBar/SettingsWindowController.swift" >/dev/null ||
        fail "Settings must expose a manual update button"
    grep -F 'onCheckForUpdates' "$ROOT_DIR/Sources/ProxyBar/SettingsWindowController.swift" >/dev/null ||
        fail "Settings must forward the update callback"
    if grep -F 'Check for Updates…' "$ROOT_DIR/Sources/ProxyBar/ApplicationMenu.swift" >/dev/null; then
        fail "application menu must not expose the update command"
    fi
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash Tests/PackageAppTests/package-app-tests.sh
```

Expected: failure containing `AppDelegate must connect the Settings update callback`.

- [ ] **Step 3: Add Settings callback forwarding**

Add `onCheckForUpdates: (() -> Void)?` to both settings controller classes.
In `SettingsWindowController.init`, forward the view-controller callback:

```swift
settingsViewController.onCheckForUpdates = { [weak self] in
    self?.onCheckForUpdates?()
}
```

- [ ] **Step 4: Build the version footer row**

Create an `NSButton`:

```swift
private lazy var checkForUpdatesButton = NSButton(
    title: "Check for Updates…",
    target: self,
    action: #selector(checkForUpdates)
)
```

Set its bezel style to `.rounded`, then replace the standalone version label in
the main stack with:

```swift
let versionRow = NSStackView(views: [versionLabel, NSView(), checkForUpdatesButton])
versionRow.orientation = .horizontal
versionRow.alignment = .centerY
versionRow.spacing = 12
```

Constrain `versionRow.widthAnchor` to 312 points and add:

```swift
@objc private func checkForUpdates() {
    onCheckForUpdates?()
}
```

- [ ] **Step 5: Wire AppDelegate and simplify the menu**

After constructing `settingsWindowController`, set:

```swift
settingsWindowController.onCheckForUpdates = { [weak self] in
    self?.updaterController.checkForUpdates(nil)
}
```

Change `ApplicationMenu.install(updaterController:)` back to
`ApplicationMenu.install()`. Remove its Sparkle import, update item, target,
and separator.

- [ ] **Step 6: Run tests and build**

Run:

```bash
bash Tests/PackageAppTests/package-app-tests.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run ProxyBarCoreTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build --product ProxyBar
```

Expected: packaging tests and core tests pass; ProxyBar builds successfully.

- [ ] **Step 7: Commit**

```bash
git add Sources/ProxyBar/SettingsWindowController.swift Sources/ProxyBar/AppDelegate.swift Sources/ProxyBar/ApplicationMenu.swift Tests/PackageAppTests/package-app-tests.sh
git commit -m "feat: move update check to settings"
```

### Task 2: Final Verification

**Files:**
- Verify: all modified files

- [ ] **Step 1: Run fresh verification**

Run:

```bash
bash -n scripts/package-app.sh
bash Tests/PackageAppTests/package-app-tests.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run ProxyBarCoreTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release --product ProxyBar
git diff --check
git status --short
```

Expected: all commands exit zero and the worktree is clean after the commit.

- [ ] **Step 2: Review requirements**

Confirm from the diff that:

- the application menu contains no update item;
- Settings shows the button beside the version label;
- Settings has no Sparkle import;
- `AppDelegate` remains the only Sparkle owner;
- pressing the Settings button invokes the standard updater controller.
