import Foundation

public enum DomainRules {
    public enum ValidationError: Error, LocalizedError {
        case empty
        case invalidHost(String)

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "Enter a domain name."
            case .invalidHost(let value):
                return "'\(value)' is not a valid domain."
            }
        }
    }

    public static func entries(for input: String, addWildcard: Bool = true) throws -> [String] {
        let host = try normalizedHost(from: input)

        if isExactOnly(host) {
            return [host]
        }

        if addWildcard {
            let apex = host.hasPrefix("*.") ? String(host.dropFirst(2)) : host
            return [apex, "*.\(apex)"]
        } else {
            return [host]
        }
    }

    public static func removalEntries(for input: String) throws -> Set<String> {
        Set(try entries(for: input, addWildcard: true))
    }

    public static func dedupedAndSorted(_ domains: [String]) -> [String] {
        let unique = Set(domains.compactMap { try? normalizedConfigEntry($0) })
        return unique.sorted { lhs, rhs in
            let lhsKey = sortKey(lhs)
            let rhsKey = sortKey(rhs)
            if lhsKey.base != rhsKey.base {
                return lhsKey.base < rhsKey.base
            }
            return lhsKey.isWildcard == false && rhsKey.isWildcard == true
        }
    }

    private static func normalizedHost(from input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.empty
        }

        let withoutURLParts: String
        if let components = URLComponents(string: trimmed),
           let host = components.host,
           trimmed.contains("://") {
            withoutURLParts = host
        } else {
            withoutURLParts = String(trimmed.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first ?? "")
        }

        return try normalizedConfigEntry(withoutURLParts)
    }

    private static func normalizedConfigEntry(_ input: String) throws -> String {
        let lowercased = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard !lowercased.isEmpty else {
            throw ValidationError.empty
        }

        let host = lowercased.hasPrefix("*.") ? String(lowercased.dropFirst(2)) : lowercased
        guard isValid(host) else {
            throw ValidationError.invalidHost(input)
        }

        return lowercased.hasPrefix("*.") ? "*.\(host)" : host
    }

    private static func isValid(_ host: String) -> Bool {
        if host == "localhost" {
            return true
        }

        guard host.contains(".") else {
            return false
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard !label.isEmpty, label.count <= 63 else {
                return false
            }

            guard label.first?.isAllowedEdgeCharacter == true,
                  label.last?.isAllowedEdgeCharacter == true else {
                return false
            }

            return label.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-"
            }
        }
    }

    private static func isExactOnly(_ host: String) -> Bool {
        host == "localhost"
    }

    private static func sortKey(_ domain: String) -> (base: String, isWildcard: Bool) {
        if domain.hasPrefix("*.") {
            return (String(domain.dropFirst(2)), true)
        }
        return (domain, false)
    }
}

private extension Character {
    var isAllowedEdgeCharacter: Bool {
        isLetter || isNumber
    }
}
