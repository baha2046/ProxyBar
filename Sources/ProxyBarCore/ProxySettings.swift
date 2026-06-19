import Foundation

public struct ProxySettings: Equatable, Sendable {
    public var socksPort: UInt16
    public var pacPort: UInt16
    public var domains: [String]
    public var dohServers: [String]

    public init(socksPort: UInt16, pacPort: UInt16, domains: [String], dohServers: [String]) {
        self.socksPort = socksPort
        self.pacPort = pacPort
        self.domains = domains
        self.dohServers = dohServers
    }

    public var pacURL: String {
        "http://127.0.0.1:\(pacPort)/proxy.pac"
    }

    public static let crabbyDefaults = ProxySettings(
        socksPort: 1080,
        pacPort: 1081,
        domains: [
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
        ],
        dohServers: [
            "https://1.1.1.1/dns-query",
            "https://8.8.8.8/dns-query",
            "https://9.9.9.9:5053/dns-query"
        ]
    )
}

public enum DomainRoutingMode: String, CaseIterable, Sendable {
    case excludeListed
    case excludeUnlisted

    public var settingsTitle: String {
        switch self {
        case .excludeListed:
            return "Listed Domains"
        case .excludeUnlisted:
            return "Unlisted Domains"
        }
    }
}

public enum CrabbyProxyConfigParser {
    public enum ParseError: Error, LocalizedError {
        case invalidPort(String)

        public var errorDescription: String? {
            switch self {
            case .invalidPort(let value):
                return "'\(value)' is not a valid proxy port."
            }
        }
    }

    public static func load(from url: URL = ConfigStore.defaultConfigURL()) -> ProxySettings {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let settings = try? parse(text) else {
            return .crabbyDefaults
        }
        return settings
    }

    public static func parse(_ text: String) throws -> ProxySettings {
        let sections = sections(in: text)
        let defaults = ProxySettings.crabbyDefaults

        let proxy = sections["proxy"] ?? []
        let doh = sections["doh"] ?? []

        return ProxySettings(
            socksPort: try port(named: "socks_port", in: proxy) ?? defaults.socksPort,
            pacPort: try port(named: "pac_port", in: proxy) ?? defaults.pacPort,
            domains: stringsArray(named: "domains", in: proxy) ?? defaults.domains,
            dohServers: stringsArray(named: "servers", in: doh) ?? defaults.dohServers
        )
    }

    private static func sections(in text: String) -> [String: [String]] {
        var current = ""
        var result: [String: [String]] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("["),
               line.hasSuffix("]"),
               !line.hasPrefix("[[") {
                current = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                result[current, default: []] = []
            } else if !current.isEmpty {
                result[current, default: []].append(rawLine)
            }
        }

        return result
    }

    private static func port(named name: String, in lines: [String]) throws -> UInt16? {
        guard let value = scalar(named: name, in: lines) else {
            return nil
        }
        guard let port = UInt16(value) else {
            throw ParseError.invalidPort(value)
        }
        return port
    }

    private static func scalar(named name: String, in lines: [String]) -> String? {
        for line in lines {
            let code = stripComment(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard code.hasPrefix("\(name)") else {
                continue
            }
            let parts = code.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else {
                continue
            }
            return String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func stringsArray(named name: String, in lines: [String]) -> [String]? {
        guard let start = lines.firstIndex(where: { stripComment(from: $0).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("\(name)") && $0.contains("[") }) else {
            return nil
        }

        var block = ""
        for line in lines[start...] {
            block += line
            block += "\n"
            if stripComment(from: line).contains("]") {
                break
            }
        }

        return extractQuotedStrings(from: block)
    }

    private static func extractQuotedStrings(from block: String) -> [String] {
        var values: [String] = []
        for line in block.components(separatedBy: .newlines) {
            let code = stripComment(from: line)
            var remainder = code[code.startIndex...]
            while let firstQuote = remainder.firstIndex(of: "\"") {
                let afterFirstQuote = remainder.index(after: firstQuote)
                guard let secondQuote = remainder[afterFirstQuote...].firstIndex(of: "\"") else {
                    break
                }
                values.append(String(remainder[afterFirstQuote..<secondQuote]))
                remainder = remainder[remainder.index(after: secondQuote)...]
            }
        }
        return values
    }

    private static func stripComment(from line: String) -> String {
        String(line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }
}

public enum PACGenerator {
    public static func generate(
        domains: [String],
        socksPort: UInt16,
        routingMode: DomainRoutingMode = .excludeListed
    ) -> String {
        guard !domains.isEmpty else {
            switch routingMode {
            case .excludeListed:
                return "function FindProxyForURL(url, host) {\n  return \"DIRECT\";\n}\n"
            case .excludeUnlisted:
                return """
                function FindProxyForURL(url, host) {
                  return "SOCKS5 127.0.0.1:\(socksPort)";
                }

                """
            }
        }

        let last = domains.count - 1
        let conditions = domains.enumerated().map { index, domain in
            let escaped = domain.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            switch (index == 0, index == last) {
            case (true, true):
                return "  if (shExpMatch(host, \"\(escaped)\"))"
            case (true, false):
                return "  if (shExpMatch(host, \"\(escaped)\") ||"
            case (false, false):
                return "      shExpMatch(host, \"\(escaped)\") ||"
            case (false, true):
                return "      shExpMatch(host, \"\(escaped)\"))"
            }
        }

        let matchedReturn: String
        let fallbackReturn: String
        switch routingMode {
        case .excludeListed:
            matchedReturn = "SOCKS5 127.0.0.1:\(socksPort)"
            fallbackReturn = "DIRECT"
        case .excludeUnlisted:
            matchedReturn = "DIRECT"
            fallbackReturn = "SOCKS5 127.0.0.1:\(socksPort)"
        }

        return """
        function FindProxyForURL(url, host) {
        \(conditions.joined(separator: "\n"))
            return "\(matchedReturn)";
          return "\(fallbackReturn)";
        }

        """
    }
}
