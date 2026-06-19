import Foundation

public struct ConfigDocument {
    public enum ParseError: Error, LocalizedError {
        case missingProxySection
        case missingDomainsArray
        case unterminatedDomainsArray

        public var errorDescription: String? {
            switch self {
            case .missingProxySection:
                return "Could not find a [proxy] section in config.toml."
            case .missingDomainsArray:
                return "Could not find proxy.domains in config.toml."
            case .unterminatedDomainsArray:
                return "proxy.domains is missing its closing bracket."
            }
        }
    }

    public let text: String
    public let domains: [String]
    public let needsRepair: Bool

    private let blockRange: Range<String.Index>
    private let blockPrefix: String
    private let blockSuffix: String

    public init(text: String) throws {
        self.text = text

        let lines = Self.lines(in: text)
        guard let proxyIndex = lines.firstIndex(where: { $0.trimmed == "[proxy]" }) else {
            self.blockRange = text.endIndex..<text.endIndex
            self.blockPrefix = Self.appendedProxySectionPrefix(for: text)
            self.blockSuffix = ""
            self.domains = []
            self.needsRepair = true
            return
        }

        let proxyEnd = lines[(proxyIndex + 1)...].firstIndex { line in
            line.trimmed.hasPrefix("[") && line.trimmed.hasSuffix("]")
        } ?? lines.endIndex

        guard let domainsStart = lines[proxyIndex..<proxyEnd].firstIndex(where: { line in
            line.trimmed.hasPrefix("domains") && line.trimmed.contains("[")
        }) else {
            let insertionIndex = Self.domainsInsertionIndex(in: lines, proxyIndex: proxyIndex, proxyEnd: proxyEnd)
            self.blockRange = insertionIndex..<insertionIndex
            self.blockPrefix = Self.insertionPrefix(in: text, at: insertionIndex)
            self.blockSuffix = Self.insertionSuffix(in: text, at: insertionIndex)
            self.domains = []
            self.needsRepair = true
            return
        }

        guard let domainsEnd = lines[domainsStart..<proxyEnd].firstIndex(where: { line in
            line.trimmed == "]" || line.trimmed == "],"
        }) else {
            throw ParseError.unterminatedDomainsArray
        }

        self.blockRange = lines[domainsStart].range.lowerBound..<lines[domainsEnd].range.upperBound
        self.blockPrefix = ""
        self.blockSuffix = ""
        self.domains = Self.extractDomains(from: String(text[blockRange]))
        self.needsRepair = false
    }

    public func replacingDomains(_ domains: [String]) throws -> String {
        let normalized = DomainRules.dedupedAndSorted(domains)
        let replacement = blockPrefix + Self.renderDomains(normalized) + blockSuffix
        var updated = text
        updated.replaceSubrange(blockRange, with: replacement)
        return updated
    }

    private static func extractDomains(from block: String) -> [String] {
        block
            .components(separatedBy: .newlines)
            .compactMap { line in
                let code = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                guard let firstQuote = code.firstIndex(of: "\"") else {
                    return nil
                }
                let afterFirstQuote = code.index(after: firstQuote)
                guard let secondQuote = code[afterFirstQuote...].firstIndex(of: "\"") else {
                    return nil
                }
                return String(code[afterFirstQuote..<secondQuote])
            }
    }

    private static func renderDomains(_ domains: [String]) -> String {
        let rendered = domains.enumerated().map { index, domain in
            let suffix = index == domains.count - 1 ? "" : ","
            return "    \"\(domain)\"\(suffix)"
        }.joined(separator: "\n")

        if rendered.isEmpty {
            return "domains = [\n]"
        }
        return "domains = [\n\(rendered)\n]"
    }

    private static func appendedProxySectionPrefix(for text: String) -> String {
        guard !text.isEmpty else {
            return "[proxy]\n"
        }
        if text.hasSuffix("\n\n") {
            return "[proxy]\n"
        }
        if text.hasSuffix("\n") {
            return "\n[proxy]\n"
        }
        return "\n\n[proxy]\n"
    }

    private static func domainsInsertionIndex(in lines: [ConfigLine], proxyIndex: Int, proxyEnd: Int) -> String.Index {
        var index = proxyEnd
        while index > proxyIndex + 1 {
            index -= 1
            if !lines[index].trimmed.isEmpty {
                return lines[index].range.upperBound
            }
        }
        return lines[proxyIndex].range.upperBound
    }

    private static func insertionPrefix(in text: String, at index: String.Index) -> String {
        guard index > text.startIndex else {
            return ""
        }
        let previous = text.index(before: index)
        return text[previous] == "\n" ? "" : "\n"
    }

    private static func insertionSuffix(in text: String, at index: String.Index) -> String {
        guard index < text.endIndex else {
            return ""
        }
        return text[index] == "\n" ? "" : "\n"
    }

    private static func lines(in text: String) -> [ConfigLine] {
        var result: [ConfigLine] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byLines, .substringNotRequired]) { _, range, enclosingRange, _ in
            let fullRange = enclosingRange
            let line = String(text[range])
            result.append(ConfigLine(range: fullRange, trimmed: line.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return result
    }

    private struct ConfigLine {
        let range: Range<String.Index>
        let trimmed: String
    }
}
