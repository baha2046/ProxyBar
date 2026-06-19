import Foundation

public final class ConfigStore {
    public let configURL: URL
    public static let sampleConfigText = """
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
    """

    public init(configURL: URL = ConfigStore.defaultConfigURL()) {
        self.configURL = configURL
    }

    public func loadDomains() throws -> [String] {
        let document = try loadDocument()
        return document.domains
    }

    @discardableResult
    public func add(input: String) throws -> [String] {
        let additions = try DomainRules.entries(for: input)
        let document = try loadDocument()
        let domains = DomainRules.dedupedAndSorted(document.domains + additions)
        try backupAndWrite(document: document, domains: domains)
        return domains
    }

    @discardableResult
    public func remove(input: String) throws -> [String] {
        let removals = try DomainRules.removalEntries(for: input)
        let document = try loadDocument()
        let domains = DomainRules.dedupedAndSorted(document.domains.filter { domain in
            !removals.contains(domain.lowercased())
        })
        try backupAndWrite(document: document, domains: domains)
        return domains
    }

    public func rewriteCurrentDomains() throws {
        let document = try loadDocument()
        let domains = DomainRules.dedupedAndSorted(document.domains)
        try backupAndWrite(document: document, domains: domains)
    }

    public static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("crabbyproxy")
            .appendingPathComponent("config.toml")
    }

    private func loadDocument() throws -> ConfigDocument {
        try ensureConfigExists()
        let text = try String(contentsOf: configURL, encoding: .utf8)
        return try ConfigDocument(text: text)
    }

    private func ensureConfigExists() throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.sampleConfigText.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func backupAndWrite(document: ConfigDocument, domains: [String]) throws {
        let updated = try document.replacingDomains(domains)
        let backupURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("config.toml.\(Self.backupTimestamp()).bak")
        try FileManager.default.copyItem(at: configURL, to: backupURL)
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
