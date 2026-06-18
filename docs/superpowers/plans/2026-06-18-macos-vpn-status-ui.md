# macOS VPN Status UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display current macOS VPN status in the ProxyBar popover using `scutil --nc list`.

**Architecture:** Add a testable `VPNStatus` parser and command-backed reader in `ProxyBarCore`. `AppDelegate` owns a timer that refreshes VPN status and feeds it into the existing AppKit view model. `ProxyStatusViewController` renders VPN status as a fourth status card matching the current panel.

**Tech Stack:** Swift 6, AppKit, Swift Package Manager, `/usr/sbin/scutil --nc list`.

---

## File Structure

- `Sources/ProxyBarCore/VPNStatus.swift`: VPN status model, parser, and command-backed reader.
- `Tests/ProxyBarCoreTests/main.swift`: parser tests for connected, disconnected, and multiple-service output.
- `Sources/ProxyBar/AppDelegate.swift`: timer-backed refresh and view model wiring.
- `Sources/ProxyBar/ProxyStatusPopover.swift`: fourth VPN card in the popover.

### Task 1: VPN Parser

**Files:**
- Create: `Sources/ProxyBarCore/VPNStatus.swift`
- Modify: `Tests/ProxyBarCoreTests/main.swift`

- [ ] **Step 1: Write failing parser tests**

Add tests that call `VPNStatus.parseScutilNCList(_:)` with representative `scutil --nc list` output:

```swift
private static func testVPNStatusParsesConnectedService() {
    let output = """
    Available network connection services in the current set (*=enabled):
    * (Connected)   A1B2C3D4-E5F6-47AA-8888-999999999999 "Work VPN" [VPN]
    * (Disconnected) 11111111-2222-3333-4444-555555555555 "Personal VPN" [VPN]
    """
    expectEqual(VPNStatus.parseScutilNCList(output), .connected(name: "Work VPN"))
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift run ProxyBarCoreTests`

Expected: compile failure because `VPNStatus` does not exist.

- [ ] **Step 3: Add minimal parser implementation**

Create `VPNStatus.swift` with a public enum, `displayName`, `isConnected`, `parseScutilNCList(_:)`, and `current(commandRunner:)`.

- [ ] **Step 4: Run tests to verify parser passes**

Run: `swift run ProxyBarCoreTests`

Expected: all tests pass.

### Task 2: UI Wiring

**Files:**
- Modify: `Sources/ProxyBar/AppDelegate.swift`
- Modify: `Sources/ProxyBar/ProxyStatusPopover.swift`

- [ ] **Step 1: Extend the view model**

Add `vpnStatus: VPNStatus` to `ProxyStatusViewModel` and pass the stored value from every `AppDelegate.viewModel(status:)` branch.

- [ ] **Step 2: Add refresh ownership**

In `AppDelegate`, add `private var vpnStatus = VPNStatus.disconnected`, `private var vpnRefreshTimer: Timer?`, `startVPNStatusMonitoring()`, and `refreshVPNStatus()`. Call the monitor on launch, invalidate it on termination, and force refresh when opening the popover.

- [ ] **Step 3: Render the VPN card**

Add `private let vpnCard = StatusCardView(title: "VPN")`, include it in the card stack, and update it with the VPN display name and green/red state.

- [ ] **Step 4: Build**

Run: `swift build --product ProxyBar`

Expected: build succeeds.

### Task 3: Verification

**Files:**
- No new files.

- [ ] **Step 1: Run core tests**

Run: `swift run ProxyBarCoreTests`

Expected: `ProxyBarCoreTests passed`.

- [ ] **Step 2: Run app build**

Run: `swift build --product ProxyBar`

Expected: build succeeds without errors.
