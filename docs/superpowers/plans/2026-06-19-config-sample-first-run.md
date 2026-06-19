# Config Sample First Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `config.sample.toml` and create `~/.config/crabbyproxy/config.toml` from sample content when the editable config is missing.

**Architecture:** Keep the behavior in `ProxyBarCore.ConfigStore`, the existing read/write boundary for config documents. Add a single canonical sample string to core and a root sample file with matching contents.

**Tech Stack:** Swift 6 package, Foundation file APIs, existing executable test target `ProxyBarCoreTests`.

---

## File Structure

- Create: `config.sample.toml` with the crabbyproxy-compatible sample config.
- Modify: `Sources/ProxyBarCore/ConfigStore.swift` to expose sample config contents and seed missing config files before document reads.
- Modify: `Tests/ProxyBarCoreTests/ProxyBarCoreTests.swift` to cover missing-file seeding.

### Task 1: Missing Config Seeding Test

**Files:**
- Modify: `Tests/ProxyBarCoreTests/ProxyBarCoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add `try testConfigStoreCreatesMissingConfigFromSample()` after `testUsesCrabbyDefaultsWhenConfigIsMissing()` in `main()`.

Add this test near the existing config tests:

```swift
private static func testConfigStoreCreatesMissingConfigFromSample() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("proxybar-config-store-\(UUID().uuidString)", isDirectory: true)
    let configURL = root
        .appendingPathComponent("crabbyproxy", isDirectory: true)
        .appendingPathComponent("config.toml")
    defer { try? FileManager.default.removeItem(at: root) }

    let domains = try ConfigStore(configURL: configURL).loadDomains()

    expect(FileManager.default.fileExists(atPath: configURL.path), "Expected missing config.toml to be created")
    expect(domains.contains("youtube.com"), "Expected seeded config to include sample domains")
    let settings = CrabbyProxyConfigParser.load(from: configURL)
    expectEqual(settings.socksPort, 1080)
    expectEqual(settings.pacPort, 1081)
    expect(settings.dohServers.contains("https://1.1.1.1/dns-query"), "Expected seeded config to include sample DoH servers")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run ProxyBarCoreTests`

Expected: fails because `ConfigStore.loadDomains()` still tries to read the missing file.

### Task 2: Sample Config and Seeding Implementation

**Files:**
- Create: `config.sample.toml`
- Modify: `Sources/ProxyBarCore/ConfigStore.swift`

- [ ] **Step 1: Add sample config file**

Create `config.sample.toml` with:

```toml
[proxy]
socks_port = 1080
pac_port = 1081
domains = [
    "*.youtube.com",
    "youtube.com",
    "*.googlevideo.com",
    "*.ytimg.com",
    "*.youtube-nocookie.com",
    "youtube-nocookie.com",
    "*.ggpht.com",
    "*.googleapis.com",
    "*.reddit.com",
    "reddit.com",
    "*.redd.it",
    "*.redditstatic.com",
    "*.hulu.com",
    "hulu.com",
    "*.hulustream.com",
    "*.huluim.com",
    "*.netflix.com",
    "netflix.com",
    "*.nflxvideo.net",
    "*.nflximg.net",
    "*.nflxso.net",
    "*.nflxext.com"
]

[doh]
servers = [
    "https://1.1.1.1/dns-query",
    "https://8.8.8.8/dns-query",
    "https://9.9.9.9:5053/dns-query"
]
```

- [ ] **Step 2: Add seeding code to `ConfigStore`**

Add a public `sampleConfigText` constant and call `ensureConfigExists()` before reading:

```swift
public static let sampleConfigText = """
[proxy]
socks_port = 1080
pac_port = 1081
domains = [
...
]

[doh]
servers = [
...
]
"""
```

`ensureConfigExists()` should check `fileExists(atPath:)`, create the parent directory with `withIntermediateDirectories: true`, and write `sampleConfigText` atomically to `configURL`.

- [ ] **Step 3: Run test to verify it passes**

Run: `swift run ProxyBarCoreTests`

Expected: `ProxyBarCoreTests passed`.

### Task 3: Documentation Check

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update configuration wording**

Change the requirements/configuration wording so it says ProxyBar creates
`~/.config/crabbyproxy/config.toml` from `config.sample.toml` on first use.

- [ ] **Step 2: Run final verification**

Run: `swift run ProxyBarCoreTests`

Expected: `ProxyBarCoreTests passed`.
