# TokenBar-Style ProxyBar UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a TokenBar-style ProxyBar popover with real proxy on/off behavior, colored status states, and clearer port bind errors.

**Architecture:** Keep proxy/server behavior in `ProxyBarCore` and expose typed lifecycle errors to the app. Replace the status item menu with a small AppKit popover controller/view owned by `AppDelegate`. `AppDelegate` remains the state coordinator and passes a render model plus callbacks into the popover.

**Tech Stack:** Swift 6, AppKit, Swift Package Manager executable targets, existing lightweight custom test runner in `Tests/ProxyBarCoreTests`.

---

## File Structure

- Modify `Sources/ProxyBarCore/PACHTTPServer.swift`: wrap bind/listen failures in a typed bind error for PAC.
- Modify `Sources/ProxyBarCore/SOCKS5Server.swift`: wrap bind/listen failures in a typed bind error for SOCKS5.
- Create `Sources/ProxyBarCore/ProxyServerError.swift`: public role/error types with user-friendly descriptions.
- Modify `Sources/ProxyBarCore/SystemActions.swift`: add `disableAutoProxy()`.
- Modify `Tests/ProxyBarCoreTests/main.swift`: add failing tests for typed PAC/SOCKS bind errors and disabling auto-proxy.
- Modify `Sources/ProxyBar/StatusIcon.swift`: render green/red/amber status variants.
- Create `Sources/ProxyBar/ProxyStatusPopover.swift`: custom TokenBar-style panel view and callback protocol.
- Modify `Sources/ProxyBar/AppDelegate.swift`: replace menu install with popover behavior, explicit proxy UI state, switch on/off actions, and improved error messages.

## Task 1: Core Bind Errors

**Files:**
- Create: `Sources/ProxyBarCore/ProxyServerError.swift`
- Modify: `Sources/ProxyBarCore/PACHTTPServer.swift`
- Modify: `Sources/ProxyBarCore/SOCKS5Server.swift`
- Test: `Tests/ProxyBarCoreTests/main.swift`

- [ ] **Step 1: Write failing tests**

Add tests that expect occupied PAC and SOCKS ports to throw `ProxyServerBindError` with role and requested port:

```swift
try testPACHTTPServerReportsOccupiedPort()
try testSOCKS5ServerReportsOccupiedPort()
```

```swift
private static func testPACHTTPServerReportsOccupiedPort() throws {
    let first = PACHTTPServer(content: "one", port: 0)
    try first.start()
    defer { first.stop() }

    let second = PACHTTPServer(content: "two", port: first.boundPort)
    do {
        try second.start()
        second.stop()
        throw TestFailure("Expected occupied PAC port to throw")
    } catch let error as ProxyServerBindError {
        expectEqual(error.role, .pac)
        expectEqual(error.port, first.boundPort)
        expect(error.localizedDescription.contains("PAC port \(first.boundPort) is already in use"), "Expected PAC-specific busy port message")
    }
}

private static func testSOCKS5ServerReportsOccupiedPort() throws {
    let first = SOCKS5Server(settings: .init(socksPort: 0, pacPort: 0, domains: [], dohServers: []))
    try first.start()
    defer { first.stop() }

    let second = SOCKS5Server(settings: .init(socksPort: first.boundPort, pacPort: 0, domains: [], dohServers: []))
    do {
        try second.start()
        second.stop()
        throw TestFailure("Expected occupied SOCKS5 port to throw")
    } catch let error as ProxyServerBindError {
        expectEqual(error.role, .socks5)
        expectEqual(error.port, first.boundPort)
        expect(error.localizedDescription.contains("SOCKS5 port \(first.boundPort) is already in use"), "Expected SOCKS5-specific busy port message")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run ProxyBarCoreTests`

Expected: compile failure because `ProxyServerBindError` does not exist, or assertion failure because occupied ports still throw raw `POSIXError`.

- [ ] **Step 3: Implement typed bind error**

Create `ProxyServerError.swift`:

```swift
import Foundation

public enum ProxyServerRole: String, Sendable {
    case socks5 = "SOCKS5"
    case pac = "PAC"

    var configKey: String {
        switch self {
        case .socks5:
            return "socks_port"
        case .pac:
            return "pac_port"
        }
    }
}

public struct ProxyServerBindError: Error, LocalizedError, Sendable {
    public let role: ProxyServerRole
    public let port: UInt16
    public let code: POSIXErrorCode

    public var errorDescription: String? {
        if code == .EADDRINUSE {
            return "\(role.rawValue) port \(port) is already in use. Quit the other app or change \(role.configKey) in config.toml."
        }
        return "\(role.rawValue) port \(port) could not be opened: \(posixErrorDescription(code.rawValue))."
    }
}
```

Wrap socket startup in `PACHTTPServer.start()` and `SOCKS5Server.start()` by catching `POSIXError` from `makeListeningSocket(port:)` and throwing `ProxyServerBindError(role:port:code:)`.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift run ProxyBarCoreTests`

Expected: `ProxyBarCoreTests passed`.

## Task 2: Disable Auto-Proxy

**Files:**
- Modify: `Sources/ProxyBarCore/SystemActions.swift`
- Test: `Tests/ProxyBarCoreTests/main.swift`

- [ ] **Step 1: Write failing test**

Add:

```swift
try testDisableAutoProxyUsesNetworksetup()
```

```swift
private static func testDisableAutoProxyUsesNetworksetup() throws {
    var commands: [RecordedCommand] = []
    let actions = SystemActions(networkService: "Wi-Fi", pacURL: "http://127.0.0.1:1081/proxy.pac") { executable, arguments in
        commands.append(RecordedCommand(executable: executable, arguments: arguments))
        return ""
    }

    try actions.disableAutoProxy()

    expectEqual(commands, [
        RecordedCommand(
            executable: "/usr/sbin/networksetup",
            arguments: ["-setautoproxystate", "Wi-Fi", "off"]
        )
    ])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run ProxyBarCoreTests`

Expected: compile failure because `disableAutoProxy()` does not exist.

- [ ] **Step 3: Implement minimal method**

Add to `SystemActions`:

```swift
public func disableAutoProxy() throws {
    try run(
        executable: "/usr/sbin/networksetup",
        arguments: ["-setautoproxystate", networkService, "off"]
    )
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift run ProxyBarCoreTests`

Expected: `ProxyBarCoreTests passed`.

## Task 3: Status Icon Variants

**Files:**
- Modify: `Sources/ProxyBar/StatusIcon.swift`

- [ ] **Step 1: Add status enum and colored rendering**

Change `StatusIcon.make()` to `StatusIcon.make(state:)` with `.running`, `.off`, `.working`, and `.failed`. Render a dark rounded proxy glyph plus a small colored status light. Use green for running, red for off/failed, amber for working.

- [ ] **Step 2: Build**

Run: `swift build --product ProxyBar`

Expected: build succeeds.

## Task 4: Custom Popover View

**Files:**
- Create: `Sources/ProxyBar/ProxyStatusPopover.swift`

- [ ] **Step 1: Implement reusable render model and view**

Create:

```swift
struct ProxyStatusViewModel {
    var title: String
    var detail: String
    var status: StatusIcon.State
    var isOn: Bool
    var socksPort: UInt16?
    var pacPort: UInt16?
    var domainCount: Int
    var errorMessage: String?
    var openAtLogin: Bool
}
```

Create `ProxyStatusViewController` with callback closures for toggling proxy, add domain, apply, open config, toggle login, and quit. Build the view in code with dark AppKit controls, a custom switch button, status cards, activity bars, and footer action buttons.

- [ ] **Step 2: Build**

Run: `swift build --product ProxyBar`

Expected: build succeeds.

## Task 5: AppDelegate State and Popover Wiring

**Files:**
- Modify: `Sources/ProxyBar/AppDelegate.swift`

- [ ] **Step 1: Replace status menu with popover**

Use `statusItem.button?.action = #selector(togglePopover)` and `statusItem.button?.target = self`. Own an `NSPopover` and `ProxyStatusViewController`.

- [ ] **Step 2: Add explicit state**

Add:

```swift
private enum ProxyUIState {
    case starting
    case running(socksPort: UInt16, pacPort: UInt16)
    case stopping
    case off
    case failed(String)
}
```

Derive `ProxyStatusViewModel` from that state and current domain count.

- [ ] **Step 3: Implement switch behavior**

`setProxyEnabled(true)` starts the server and applies PAC settings. `setProxyEnabled(false)` stops the server, disables auto-proxy, and updates state to off. Failed start stops partial server state and shows the localized error.

- [ ] **Step 4: Preserve actions**

Wire Add Domain, Apply Now, Open Config, Open at Login, and Quit into callbacks. `Apply Now` reloads and reapplies only when on; when off it rewrites config/domain data and updates the panel without starting.

- [ ] **Step 5: Build**

Run: `swift build --product ProxyBar`

Expected: build succeeds.

## Task 6: Final Verification

**Files:**
- All modified source and test files.

- [ ] **Step 1: Run core tests**

Run: `swift run ProxyBarCoreTests`

Expected: `ProxyBarCoreTests passed`.

- [ ] **Step 2: Run app build**

Run: `swift build --product ProxyBar`

Expected: build succeeds.

- [ ] **Step 3: Review diff**

Run: `git diff --stat` and `git diff --check`.

Expected: focused changes, no whitespace errors.
