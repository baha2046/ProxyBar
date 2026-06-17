import Foundation
import ProxyBarCore

@main
struct ProxyBarCoreTests {
    static func main() throws {
        try testApexDomainExpandsToPair()
        try testWildcardDomainExpandsToPair()
        try testLocalhostRemainsExactOnly()
        try testURLInputUsesHost()
        testDedupeAndSortKeepsUniqueDomains()
        try testInvalidInputIsRejected()
        try testExtractsDomains()
        try testReplacesOnlyDomainBlock()
        try testMissingDomainBlockReportsError()
        try testRefreshPACUsesValidNetworksetupArguments()
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

    private static func testMissingDomainBlockReportsError() throws {
        do {
            _ = try ConfigDocument(text: "[proxy]\nsocks_port = 1080\n")
            throw TestFailure("Expected missing domain block to throw")
        } catch is ConfigDocument.ParseError {
        }
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
