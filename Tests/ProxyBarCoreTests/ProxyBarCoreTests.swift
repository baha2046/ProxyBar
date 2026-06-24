import Foundation
import ProxyBarCore

@main
struct ProxyBarCoreTests {
    static func main() async throws {
        try testApexDomainExpandsToPair()
        try testWildcardDomainExpandsToPair()
        try testApexDomainWithoutWildcard()
        try testWildcardDomainWithoutWildcard()
        try testLocalhostRemainsExactOnly()
        try testURLInputUsesHost()
        testDedupeAndSortKeepsUniqueDomains()
        try testInvalidInputIsRejected()
        try testExtractsDomains()
        try testParsesProxySettings()
        try testUsesCrabbyDefaultsWhenConfigIsMissing()
        try testConfigStoreCreatesMissingConfigFromSample()
        testAppVersionDisplayUsesShortVersionAndBuildNumber()
        testGeneratesPACFromSettings()
        testGeneratesPACForOppositeRoutingMode()
        try testReplacesOnlyDomainBlock()
        try testAddsDomainsArrayToExistingProxySection()
        try testAddsProxySectionWhenMissing()
        try testConfigStoreRepairsMissingDomainBlock()
        try testConfigStoreRepairsMissingProxySection()
        try testRefreshPACUsesValidNetworksetupArguments()
        try testRefreshPACSupportsMultipleNetworkServices()
        try testApplyRefreshesPACWithoutLaunchctl()
        try testDisableAutoProxyUsesNetworksetup()
        try testDisableAutoProxySupportsMultipleNetworkServices()
        testProxyNetworkScopeProvidesDisplayLabels()
        testNetworkServiceResolverParsesServices()
        try testNetworkServiceResolverFindsActiveDefaultService()
        try testNetworkServiceResolverIgnoresDisabledActiveDefaultService()
        try testSystemActionsRefreshUsesActiveNetworkServiceWhenNoneProvided()
        try testSystemActionsDefaultInitializerUsesActiveNetworkService()
        try testNetworkServiceResolverFindsUSBLAN()
        try testNetworkServiceResolverFindsThunderboltEthernet()
        try testNetworkServiceResolverIgnoresBridgeAndVPNServices()
        testProxyPopoverCardsFitContentWidth()
        testLiquidGlassRequiresMacOS26()
        testMouseHoverStateClearsWhenContentScrolls()
        testDomainListUpdateStateSkipsUnchangedDomains()
        testDomainListUpdateStateRendersAfterSkippedRefresh()
        testAddDomainPresentationUsesActivePopoverWindow()
        testVPNStatusParsesConnectedService()
        testVPNStatusParsesDisconnectedServices()
        testVPNStatusUsesFirstConnectedService()
        testRequestActivityTimelineBucketsRequestsByMinute()
        try await testPACHTTPServerServesProxyPAC()
        try testPACHTTPServerReportsOccupiedPort()
        try testSOCKS5ServerReportsOccupiedPort()
        try testSOCKS5ServerRejectsNonSocksGreeting()
        try testSOCKS5ServerCountsValidConnectRequests()
        try testSOCKS5ServerHandlesFragmentedRequest()
        try await testEmbeddedProxyServerReloadsSettings()
        try await testEmbeddedProxyServerReloadPreservesRoutingMode()
        print("ProxyBarCoreTests passed")
    }

    private static func testApexDomainExpandsToPair() throws {
        let domains = try DomainRules.entries(for: "Example.com")
        expectEqual(domains, ["example.com", "*.example.com"])
    }

    private static func testWildcardDomainExpandsToPair() throws {
        let domains = try DomainRules.entries(for: "*.Example.com")
        expectEqual(domains, ["example.com", "*.example.com"])
    }

    private static func testApexDomainWithoutWildcard() throws {
        let domains = try DomainRules.entries(for: "Example.com", addWildcard: false)
        expectEqual(domains, ["example.com"])
    }

    private static func testWildcardDomainWithoutWildcard() throws {
        let domains = try DomainRules.entries(for: "*.Example.com", addWildcard: false)
        expectEqual(domains, ["*.example.com"])
    }

    private static func testLocalhostRemainsExactOnly() throws {
        let domains = try DomainRules.entries(for: "localhost")
        expectEqual(domains, ["localhost"])
    }

    private static func testURLInputUsesHost() throws {
        let domains = try DomainRules.entries(for: "https://Sub.Example.com/path?q=1")
        expectEqual(domains, ["sub.example.com", "*.sub.example.com"])
    }

    private static func testDedupeAndSortKeepsUniqueDomains() {
        let domains = DomainRules.dedupedAndSorted([
            "*.example.com",
            "localhost",
            "example.com",
            "Example.com",
            "*.Example.com"
        ])
        expectEqual(domains, ["example.com", "*.example.com", "localhost"])
    }

    private static func testInvalidInputIsRejected() throws {
        do {
            _ = try DomainRules.entries(for: "not a host!")
            throw TestFailure("Expected invalid host to throw")
        } catch is DomainRules.ValidationError {
        }
    }

    private static func testExtractsDomains() throws {
        let document = try ConfigDocument(text: sampleConfig)
        expectEqual(document.domains, [
            "*.youtube.com",
            "youtube.com",
            "*.reddit.com",
            "reddit.com"
        ])
    }

    private static func testParsesProxySettings() throws {
        let settings = try CrabbyProxyConfigParser.parse(sampleConfig)
        expectEqual(settings.socksPort, 1080)
        expectEqual(settings.pacPort, 1081)
        expectEqual(settings.dohServers, ["https://1.1.1.1/dns-query"])
        expectEqual(settings.domains, [
            "*.youtube.com",
            "youtube.com",
            "*.reddit.com",
            "reddit.com"
        ])
    }

    private static func testUsesCrabbyDefaultsWhenConfigIsMissing() throws {
        let settings = CrabbyProxyConfigParser.load(from: URL(fileURLWithPath: "/tmp/proxybar-missing-config-\(UUID().uuidString).toml"))
        expectEqual(settings.socksPort, 1080)
        expectEqual(settings.pacPort, 1081)
        expect(settings.dohServers.contains("https://1.1.1.1/dns-query"), "Expected Cloudflare DoH default")
        expect(settings.domains.contains("youtube.com"), "Expected crabbyproxy default domains")
    }

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

    private static func testAppVersionDisplayUsesShortVersionAndBuildNumber() {
        let display = AppVersionDisplay.string(info: [
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "7"
        ])

        expectEqual(display, "Version 1.0.0 (Build 7)")
        expectEqual(AppVersionDisplay.string(info: [:]), "Version unknown")
    }

    private static func testGeneratesPACFromSettings() {
        let pac = PACGenerator.generate(domains: ["*.example.com", "example.com"], socksPort: 1088)
        expect(pac.contains(#"shExpMatch(host, "*.example.com")"#), "Expected wildcard condition")
        expect(pac.contains(#"return "SOCKS5 127.0.0.1:1088";"#), "Expected SOCKS5 return")
        expect(pac.contains(#"return "DIRECT";"#), "Expected DIRECT fallback")

        let direct = PACGenerator.generate(domains: [], socksPort: 1088)
        expect(!direct.contains("SOCKS5"), "Expected empty domains to render DIRECT-only PAC")
    }

    private static func testGeneratesPACForOppositeRoutingMode() {
        let pac = PACGenerator.generate(
            domains: ["*.example.com", "example.com"],
            socksPort: 1088,
            routingMode: .excludeUnlisted
        )

        expect(pac.contains(#"shExpMatch(host, "*.example.com")"#), "Expected wildcard condition")
        expect(pac.contains(#"return "DIRECT";"#), "Expected configured domains to use VPN/direct routing")
        expect(pac.contains(#"return "SOCKS5 127.0.0.1:1088";"#), "Expected unlisted domains to bypass VPN through SOCKS5")
        expect(pac.range(of: #"return "DIRECT";"#)!.lowerBound < pac.range(of: #"return "SOCKS5 127.0.0.1:1088";"#)!.lowerBound, "Expected direct return before SOCKS5 fallback")
    }

    private static func testProxyPopoverCardsFitContentWidth() {
        let metrics = ProxyPopoverLayoutMetrics(
            panelWidth: 440,
            horizontalInset: 18,
            cardSpacing: 10,
            cardCount: 3
        )

        expectEqual(metrics.contentWidth, 404)
        expectEqual(metrics.cardWidth, 127)
        expectEqual(metrics.cardsTotalWidth, 401)
        expect(metrics.cardsTotalWidth <= metrics.contentWidth, "Expected status cards to fit within popover content width")
    }


    private static func testMouseHoverStateClearsWhenContentScrolls() {
        var hoverState = MouseHoverState()

        hoverState.mouseEntered()
        expect(hoverState.isActive, "Expected mouse-enter to activate hover state")

        hoverState.contentScrolled()
        expect(!hoverState.isActive, "Expected scroll movement to clear stale hover state")
    }

    private static func testDomainListUpdateStateSkipsUnchangedDomains() {
        var updateState = DomainListUpdateState()

        expect(updateState.shouldRender(domains: ["example.com", "*.example.com"]), "Expected first domain update to render")
        expect(!updateState.shouldRender(domains: ["example.com", "*.example.com"]), "Expected unchanged domains to skip rendering")
        expect(updateState.shouldRender(domains: ["example.com", "*.example.com", "localhost"]), "Expected changed domains to render")
    }

    private static func testDomainListUpdateStateRendersAfterSkippedRefresh() {
        var updateState = DomainListUpdateState()

        expect(updateState.shouldRender(domains: ["example.com"]), "Expected initial domain list to render")
        expect(!updateState.shouldRender(domains: ["example.com"]), "Expected cancel/no-op refresh to skip rendering")
        expect(updateState.shouldRender(domains: ["example.com", "*.example.com"]), "Expected later add to render after skipped refresh")
    }

    private static func testAddDomainPresentationUsesActivePopoverWindow() {
        expectEqual(
            AddDomainPresentationDecision.mode(popoverIsShown: true, hasPopoverWindow: true),
            .sheet
        )
        expectEqual(
            AddDomainPresentationDecision.mode(popoverIsShown: true, hasPopoverWindow: false),
            .standalone
        )
        expectEqual(
            AddDomainPresentationDecision.mode(popoverIsShown: false, hasPopoverWindow: true),
            .standalone
        )
    }


    private static func testReplacesOnlyDomainBlock() throws {
        let document = try ConfigDocument(text: sampleConfig)
        let updated = try document.replacingDomains([
            "example.com",
            "*.example.com",
            "localhost"
        ])

        expect(updated.contains("[doh]"), "Expected updated config to preserve [doh]")
        expect(updated.contains("socks_port = 1080"), "Expected updated config to preserve socks_port")
        expect(updated.contains("pac_port = 1081"), "Expected updated config to preserve pac_port")
        expect(updated.contains(#""example.com","#), "Expected updated config to contain example.com")
        expect(updated.contains(#""*.example.com","#), "Expected updated config to contain wildcard example.com")
        expect(updated.contains(#""localhost""#), "Expected updated config to contain localhost")
        expect(!updated.contains("youtube.com"), "Expected updated config to remove youtube.com")
        expect(!updated.contains("reddit.com"), "Expected updated config to remove reddit.com")
    }

    private static func testAddsDomainsArrayToExistingProxySection() throws {
        let document = try ConfigDocument(text: """
        [proxy]
        socks_port = 1090

        [doh]
        servers = [
            "https://1.1.1.1/dns-query",
        ]
        """)

        expectEqual(document.domains, [])

        let updated = try document.replacingDomains(["example.com"])

        expect(updated.contains("socks_port = 1090"), "Expected proxy settings to be preserved")
        expect(updated.contains("[doh]"), "Expected unrelated sections to be preserved")
        expect(updated.contains(#""example.com""#), "Expected repaired domains array to contain replacement domain")
        expect(updated.range(of: "[proxy]")!.lowerBound < updated.range(of: "domains = [")!.lowerBound, "Expected domains array inside proxy section")
        expect(updated.range(of: "domains = [")!.lowerBound < updated.range(of: "[doh]")!.lowerBound, "Expected domains array before next section")
    }

    private static func testAddsProxySectionWhenMissing() throws {
        let document = try ConfigDocument(text: """
        [doh]
        servers = [
            "https://1.1.1.1/dns-query",
        ]
        """)

        expectEqual(document.domains, [])

        let updated = try document.replacingDomains(["example.com"])

        expect(updated.contains("[doh]"), "Expected existing config to be preserved")
        expect(updated.contains("[proxy]"), "Expected missing proxy section to be added")
        expect(updated.contains(#""example.com""#), "Expected repaired proxy section to contain replacement domain")
    }

    private static func testConfigStoreRepairsMissingDomainBlock() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("proxybar-config-store-repair-\(UUID().uuidString)", isDirectory: true)
        let configURL = root
            .appendingPathComponent("crabbyproxy", isDirectory: true)
            .appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        [proxy]
        socks_port = 1090

        [doh]
        servers = [
            "https://1.1.1.1/dns-query",
        ]
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let domains = try ConfigStore(configURL: configURL).loadDomains()
        let repaired = try String(contentsOf: configURL, encoding: .utf8)

        expectEqual(domains, [])
        expect(repaired.contains("socks_port = 1090"), "Expected repair to preserve proxy settings")
        expect(repaired.contains("[doh]"), "Expected repair to preserve unrelated config")
        expect(repaired.contains("domains = ["), "Expected repair to add domains array")
    }

    private static func testConfigStoreRepairsMissingProxySection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("proxybar-config-store-repair-proxy-\(UUID().uuidString)", isDirectory: true)
        let configURL = root
            .appendingPathComponent("crabbyproxy", isDirectory: true)
            .appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        [doh]
        servers = [
            "https://1.1.1.1/dns-query",
        ]
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let domains = try ConfigStore(configURL: configURL).loadDomains()
        let repaired = try String(contentsOf: configURL, encoding: .utf8)

        expectEqual(domains, [])
        expect(repaired.contains("[doh]"), "Expected repair to preserve unrelated config")
        expect(repaired.contains("[proxy]"), "Expected repair to add missing proxy section")
        expect(repaired.contains("domains = ["), "Expected repair to add domains array")
    }

    private static func testRefreshPACUsesValidNetworksetupArguments() throws {
        var commands: [RecordedCommand] = []
        let actions = SystemActions(networkService: "Wi-Fi", pacURL: "http://127.0.0.1:1081/proxy.pac") { executable, arguments in
            commands.append(RecordedCommand(executable: executable, arguments: arguments))
            return ""
        }

        try actions.refreshPAC()

        expectEqual(commands, [
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Wi-Fi", "off"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxyurl", "Wi-Fi", "http://127.0.0.1:1081/proxy.pac"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Wi-Fi", "on"]
            )
        ])
    }

    private static func testRefreshPACSupportsMultipleNetworkServices() throws {
        var commands: [RecordedCommand] = []
        let actions = SystemActions(networkServices: ["Wi-Fi", "Ethernet"], pacURL: "http://127.0.0.1:1081/proxy.pac") { executable, arguments in
            commands.append(RecordedCommand(executable: executable, arguments: arguments))
            return ""
        }

        try actions.refreshPAC()

        expectEqual(commands, [
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Wi-Fi", "off"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxyurl", "Wi-Fi", "http://127.0.0.1:1081/proxy.pac"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Wi-Fi", "on"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Ethernet", "off"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxyurl", "Ethernet", "http://127.0.0.1:1081/proxy.pac"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Ethernet", "on"]
            )
        ])
    }

    private static func testApplyRefreshesPACWithoutLaunchctl() throws {
        var commands: [RecordedCommand] = []
        let actions = SystemActions(settings: .init(socksPort: 1080, pacPort: 1099, domains: [], dohServers: []), networkService: "Wi-Fi") { executable, arguments in
            commands.append(RecordedCommand(executable: executable, arguments: arguments))
            return ""
        }

        try actions.apply()

        expectEqual(commands, [
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Wi-Fi", "off"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxyurl", "Wi-Fi", "http://127.0.0.1:1099/proxy.pac"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Wi-Fi", "on"]
            )
        ])
    }

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

    private static func testDisableAutoProxySupportsMultipleNetworkServices() throws {
        var commands: [RecordedCommand] = []
        let actions = SystemActions(networkServices: ["Wi-Fi", "Ethernet"], pacURL: "http://127.0.0.1:1081/proxy.pac") { executable, arguments in
            commands.append(RecordedCommand(executable: executable, arguments: arguments))
            return ""
        }

        try actions.disableAutoProxy()

        expectEqual(commands, [
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Wi-Fi", "off"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "Ethernet", "off"]
            )
        ])
    }

    private static func testProxyNetworkScopeProvidesDisplayLabels() {
        expectEqual(ProxyNetworkScope.wifi.title, "Wi-Fi")
        expectEqual(ProxyNetworkScope.lan.title, "LAN")
        expectEqual(ProxyNetworkScope.both.title, "Both")
        expectEqual(ProxyNetworkScope.both.displayName, "Wi-Fi and LAN")
    }

    private static func testNetworkServiceResolverParsesServices() {
        let services = NetworkServiceResolver.parseListAllNetworkServices("""
        An asterisk (*) denotes that a network service is disabled.
        USB 10/100/1G/2.5G LAN
        *Thunderbolt Bridge
        Wi-Fi
        Surfshark. WireGuard
        """)

        expectEqual(services, [
            NetworkServiceResolver.Service(name: "USB 10/100/1G/2.5G LAN", isEnabled: true),
            NetworkServiceResolver.Service(name: "Thunderbolt Bridge", isEnabled: false),
            NetworkServiceResolver.Service(name: "Wi-Fi", isEnabled: true),
            NetworkServiceResolver.Service(name: "Surfshark. WireGuard", isEnabled: true)
        ])
    }

    private static func testNetworkServiceResolverFindsActiveDefaultService() throws {
        let routeOutput = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.1.1
          interface: en7
        """
        let serviceOrderOutput = """
        An asterisk (*) denotes that a network service is disabled.
        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        (2) USB 10/100/1G/2.5G LAN
        (Hardware Port: USB 10/100/1G/2.5G LAN, Device: en7)
        """

        let service = try NetworkServiceResolver.resolveActiveService(
            defaultRouteOutput: routeOutput,
            networkServiceOrderOutput: serviceOrderOutput
        )

        expectEqual(service, "USB 10/100/1G/2.5G LAN")
    }

    private static func testNetworkServiceResolverIgnoresDisabledActiveDefaultService() throws {
        let routeOutput = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.1.1
          interface: en7
        """
        let serviceOrderOutput = """
        An asterisk (*) denotes that a network service is disabled.
        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        (2) *USB 10/100/1G/2.5G LAN
        (Hardware Port: USB 10/100/1G/2.5G LAN, Device: en7)
        """

        do {
            _ = try NetworkServiceResolver.resolveActiveService(
                defaultRouteOutput: routeOutput,
                networkServiceOrderOutput: serviceOrderOutput
            )
            throw TestFailure("Expected disabled active service to throw")
        } catch NetworkServiceResolver.ResolutionError.missingActiveService("en7") {
        }
    }

    private static func testSystemActionsRefreshUsesActiveNetworkServiceWhenNoneProvided() throws {
        var commands: [RecordedCommand] = []
        let actions = SystemActions(settings: .init(socksPort: 1080, pacPort: 1099, domains: [], dohServers: [])) { executable, arguments in
            commands.append(RecordedCommand(executable: executable, arguments: arguments))
            switch (executable, arguments) {
            case ("/sbin/route", ["-n", "get", "default"]):
                return """
                   route to: default
                destination: default
                       mask: default
                    gateway: 192.168.1.1
                  interface: en7
                """
            case ("/usr/sbin/networksetup", ["-listnetworkserviceorder"]):
                return """
                An asterisk (*) denotes that a network service is disabled.
                (1) Wi-Fi
                (Hardware Port: Wi-Fi, Device: en0)

                (2) USB 10/100/1G/2.5G LAN
                (Hardware Port: USB 10/100/1G/2.5G LAN, Device: en7)
                """
            default:
                return ""
            }
        }

        try actions.refreshPAC()

        expectEqual(commands, [
            RecordedCommand(
                executable: "/sbin/route",
                arguments: ["-n", "get", "default"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-listnetworkserviceorder"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "USB 10/100/1G/2.5G LAN", "off"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxyurl", "USB 10/100/1G/2.5G LAN", "http://127.0.0.1:1099/proxy.pac"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "USB 10/100/1G/2.5G LAN", "on"]
            )
        ])
    }

    private static func testSystemActionsDefaultInitializerUsesActiveNetworkService() throws {
        var commands: [RecordedCommand] = []
        let actions = SystemActions(pacURL: "http://127.0.0.1:1081/proxy.pac") { executable, arguments in
            commands.append(RecordedCommand(executable: executable, arguments: arguments))
            switch (executable, arguments) {
            case ("/sbin/route", ["-n", "get", "default"]):
                return "interface: en7"
            case ("/usr/sbin/networksetup", ["-listnetworkserviceorder"]):
                return """
                (1) USB 10/100/1G/2.5G LAN
                (Hardware Port: USB 10/100/1G/2.5G LAN, Device: en7)
                """
            default:
                return ""
            }
        }

        try actions.refreshPAC()

        expectEqual(commands, [
            RecordedCommand(
                executable: "/sbin/route",
                arguments: ["-n", "get", "default"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-listnetworkserviceorder"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "USB 10/100/1G/2.5G LAN", "off"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxyurl", "USB 10/100/1G/2.5G LAN", "http://127.0.0.1:1081/proxy.pac"]
            ),
            RecordedCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", "USB 10/100/1G/2.5G LAN", "on"]
            )
        ])
    }

    private static func testNetworkServiceResolverFindsUSBLAN() throws {
        let services = [
            NetworkServiceResolver.Service(name: "USB 10/100/1G/2.5G LAN", isEnabled: true),
            NetworkServiceResolver.Service(name: "Wi-Fi", isEnabled: true),
            NetworkServiceResolver.Service(name: "Surfshark. WireGuard", isEnabled: true)
        ]

        expectEqual(try NetworkServiceResolver.resolve(scope: .lan, services: services), ["USB 10/100/1G/2.5G LAN"])
        expectEqual(try NetworkServiceResolver.resolve(scope: .both, services: services), ["Wi-Fi", "USB 10/100/1G/2.5G LAN"])
    }

    private static func testNetworkServiceResolverFindsThunderboltEthernet() throws {
        let services = [
            NetworkServiceResolver.Service(name: "Wi-Fi", isEnabled: true),
            NetworkServiceResolver.Service(name: "Thunderbolt Ethernet", isEnabled: true)
        ]

        expectEqual(try NetworkServiceResolver.resolve(scope: .lan, services: services), ["Thunderbolt Ethernet"])
    }

    private static func testNetworkServiceResolverIgnoresBridgeAndVPNServices() throws {
        let services = [
            NetworkServiceResolver.Service(name: "Wi-Fi", isEnabled: true),
            NetworkServiceResolver.Service(name: "Thunderbolt Bridge", isEnabled: true),
            NetworkServiceResolver.Service(name: "Surfshark. WireGuard", isEnabled: true)
        ]

        do {
            _ = try NetworkServiceResolver.resolve(scope: .lan, services: services)
            throw TestFailure("Expected missing LAN service to throw")
        } catch NetworkServiceResolver.ResolutionError.missingLANService {
        }
    }

    private static func testLiquidGlassRequiresMacOS26() {
        expect(!ProxyBarPlatformFeatures.usesLiquidGlass(on: OperatingSystemVersion(majorVersion: 25, minorVersion: 9, patchVersion: 0)), "Expected macOS 25 to keep the legacy background")
        expect(ProxyBarPlatformFeatures.usesLiquidGlass(on: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)), "Expected macOS 26 to enable Liquid Glass")
        expect(ProxyBarPlatformFeatures.usesLiquidGlass(on: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)), "Expected macOS 27 to keep Liquid Glass enabled")
    }

    private static func testVPNStatusParsesConnectedService() {
        let output = """
        Available network connection services in the current set (*=enabled):
        * (Connected)   A1B2C3D4-E5F6-47AA-8888-999999999999 "Work VPN" [VPN]
        * (Disconnected) 11111111-2222-3333-4444-555555555555 "Personal VPN" [VPN]
        """

        expectEqual(VPNStatus.parseScutilNCList(output), .connected(name: "Work VPN"))
    }

    private static func testVPNStatusParsesDisconnectedServices() {
        let output = """
        Available network connection services in the current set (*=enabled):
        * (Disconnected) A1B2C3D4-E5F6-47AA-8888-999999999999 "Work VPN" [VPN]
        * (Disconnected) 11111111-2222-3333-4444-555555555555 "Personal VPN" [VPN]
        """

        expectEqual(VPNStatus.parseScutilNCList(output), .disconnected)
    }

    private static func testVPNStatusUsesFirstConnectedService() {
        let output = """
        Available network connection services in the current set (*=enabled):
        * (Disconnected) 11111111-2222-3333-4444-555555555555 "Personal VPN" [VPN]
        * (Connected)   A1B2C3D4-E5F6-47AA-8888-999999999999 "Work VPN" [VPN]
        * (Connected)   99999999-8888-7777-6666-555555555555 "Backup VPN" [VPN]
        """

        expectEqual(VPNStatus.parseScutilNCList(output), .connected(name: "Work VPN"))
    }

    private static func testRequestActivityTimelineBucketsRequestsByMinute() {
        let timeline = RequestActivityTimeline(bucketCount: 3, bucketDuration: 60)

        timeline.record(at: Date(timeIntervalSince1970: 120))
        timeline.record(at: Date(timeIntervalSince1970: 130))
        timeline.record(at: Date(timeIntervalSince1970: 180))

        expectEqual(timeline.counts(endingAt: Date(timeIntervalSince1970: 180)), [0, 2, 1])

        timeline.reset()
        expectEqual(timeline.counts(endingAt: Date(timeIntervalSince1970: 180)), [0, 0, 0])
    }

    private static func testPACHTTPServerServesProxyPAC() async throws {
        let server = PACHTTPServer(content: "function FindProxyForURL(url, host) {\n  return \"DIRECT\";\n}\n", port: 0)
        try server.start()
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(server.boundPort)/proxy.pac")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = response as? HTTPURLResponse
        expectEqual(http?.statusCode, 200)
        expectEqual(String(data: data, encoding: .utf8), "function FindProxyForURL(url, host) {\n  return \"DIRECT\";\n}\n")
    }

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

    private static func testSOCKS5ServerRejectsNonSocksGreeting() throws {
        let server = SOCKS5Server(settings: .init(socksPort: 0, pacPort: 0, domains: [], dohServers: []))
        try server.start()
        defer { server.stop() }

        let socket = try TestSocket.connect(port: server.boundPort)
        defer { socket.close() }

        try socket.write([0x04, 0x01, 0x00])
        let response = try socket.read(maxBytes: 2)
        expectEqual(response, [])
    }

    private static func testSOCKS5ServerCountsValidConnectRequests() throws {
        let activity = RequestActivityTimeline()
        let server = SOCKS5Server(settings: .init(socksPort: 0, pacPort: 0, domains: [], dohServers: []), requestActivity: activity)
        try server.start()
        defer { server.stop() }

        let socket = try TestSocket.connect(port: server.boundPort)
        defer { socket.close() }

        try socket.write([0x05, 0x01, 0x00])
        expectEqual(try socket.read(maxBytes: 2), [0x05, 0x00])

        try socket.write([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0x00, 0x01])
        let response = try socket.read(maxBytes: 2)
        expect(response.count == 2, "Expected a SOCKS5 reply, got \(response)")
        expectEqual(activity.totalCount, 1)
    }

    private static func testSOCKS5ServerHandlesFragmentedRequest() throws {
        let server = SOCKS5Server(settings: .init(socksPort: 0, pacPort: 0, domains: [], dohServers: []))
        try server.start()
        defer { server.stop() }

        let socket = try TestSocket.connect(port: server.boundPort)
        defer { socket.close() }

        // Greeting in one write, expect method-selection reply.
        try socket.write([0x05, 0x01, 0x00])
        let greetingReply = try socket.read(maxBytes: 2)
        expectEqual(greetingReply, [0x05, 0x00])

        // CONNECT request to 127.0.0.1:1 (IPv4) sent fragmented across TCP segments.
        try? socket.write([0x05, 0x01, 0x00, 0x01])
        usleep(80_000)
        try? socket.write([127, 0, 0, 1])
        usleep(80_000)
        try? socket.write([0x00, 0x01])

        let response = try socket.read(maxBytes: 2)
        expect(response.count == 2, "Expected a SOCKS5 reply, got \(response)")
        expectEqual(response[0], 0x05)
        // 0x07 == command/request not supported (the incomplete-request rejection).
        // A correctly-parsed fragmented request must reach the connect stage instead.
        expect(response[1] != 0x07, "Fragmented request was rejected as incomplete (reply byte 0x07)")
    }

    private static func testEmbeddedProxyServerReloadsSettings() async throws {
        let server = EmbeddedProxyServer(settings: .init(socksPort: 0, pacPort: 0, domains: ["one.example"], dohServers: []))
        try server.start()
        defer { server.stop() }

        let firstPAC = try await fetchPAC(port: server.boundPACPort)
        expect(firstPAC.contains("one.example"), "Expected initial PAC content")

        try server.reload(settings: .init(socksPort: 0, pacPort: server.boundPACPort, domains: ["two.example"], dohServers: []))
        let secondPAC = try await fetchPAC(port: server.boundPACPort)
        expect(secondPAC.contains("two.example"), "Expected reloaded PAC content")
        expect(!secondPAC.contains("one.example"), "Expected old PAC content to be replaced")
    }

    private static func testEmbeddedProxyServerReloadPreservesRoutingMode() async throws {
        let server = EmbeddedProxyServer(
            settings: .init(socksPort: 0, pacPort: 0, domains: ["one.example"], dohServers: []),
            routingMode: .excludeUnlisted
        )
        try server.start()
        defer { server.stop() }

        try server.reload(settings: .init(socksPort: 0, pacPort: server.boundPACPort, domains: ["two.example"], dohServers: []))
        let pac = try await fetchPAC(port: server.boundPACPort)

        expect(pac.contains("two.example"), "Expected reloaded PAC content")
        expect(pac.range(of: #"return "DIRECT";"#)!.lowerBound < pac.range(of: #"return "SOCKS5 127.0.0.1:"#)!.lowerBound, "Expected opposite routing mode to survive reload")
    }

    private static func fetchPAC(port: UInt16) async throws -> String {
        let url = URL(string: "http://127.0.0.1:\(port)/proxy.pac")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fatalError(message)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) {
        if actual != expected {
            fatalError("Expected \(expected), got \(actual)")
        }
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }

    private struct RecordedCommand: Equatable, CustomStringConvertible {
        let executable: String
        let arguments: [String]

        var description: String {
            ([executable] + arguments).joined(separator: " ")
        }
    }

    private final class TestSocket {
        private let descriptor: Int32

        private init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        static func connect(port: UInt16) throws -> TestSocket {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let status = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard status == 0 else {
                let error = POSIXError(.init(rawValue: errno) ?? .EIO)
                Darwin.close(fd)
                throw error
            }
            return TestSocket(descriptor: fd)
        }

        func write(_ bytes: [UInt8]) throws {
            guard Darwin.write(descriptor, bytes, bytes.count) == bytes.count else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }

        func read(maxBytes: Int) throws -> [UInt8] {
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var buffer = [UInt8](repeating: 0, count: maxBytes)
            let count = Darwin.read(descriptor, &buffer, maxBytes)
            if count <= 0 {
                return []
            }
            return Array(buffer.prefix(count))
        }

        func close() {
            Darwin.close(descriptor)
        }
    }

    private static let sampleConfig = """
    [doh]
    servers = [
        "https://1.1.1.1/dns-query",      # Cloudflare
    ]

    [proxy]
    socks_port = 1080
    pac_port = 1081
    domains = [
        # YouTube
        "*.youtube.com",
        "youtube.com",
        # Reddit
        "*.reddit.com",
        "reddit.com",
    ]
    """
}
