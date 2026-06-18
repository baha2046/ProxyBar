import Foundation

public enum NetworkServiceResolver {
    public struct Service: Equatable, Sendable {
        public let name: String
        public let isEnabled: Bool

        public init(name: String, isEnabled: Bool) {
            self.name = name
            self.isEnabled = isEnabled
        }
    }

    public enum ResolutionError: Error, LocalizedError, Equatable {
        case missingWiFiService
        case missingLANService

        public var errorDescription: String? {
            switch self {
            case .missingWiFiService:
                return "Wi-Fi network service not found."
            case .missingLANService:
                return "LAN network service not found."
            }
        }
    }

    public static func resolve(
        scope: ProxyNetworkScope,
        commandRunner: SystemActions.CommandRunner = SystemActions.runProcess
    ) throws -> [String] {
        let output = try commandRunner("/usr/sbin/networksetup", ["-listallnetworkservices"])
        return try resolve(scope: scope, services: parseListAllNetworkServices(output))
    }

    public static func resolve(scope: ProxyNetworkScope, services: [Service]) throws -> [String] {
        switch scope {
        case .wifi:
            return [try wifiService(in: services)]
        case .lan:
            let lanServices = lanServices(in: services)
            guard !lanServices.isEmpty else {
                throw ResolutionError.missingLANService
            }
            return lanServices
        case .both:
            let lanServices = lanServices(in: services)
            guard !lanServices.isEmpty else {
                throw ResolutionError.missingLANService
            }
            return [try wifiService(in: services)] + lanServices
        }
    }

    public static func parseListAllNetworkServices(_ output: String) -> [Service] {
        output.components(separatedBy: .newlines).compactMap { rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.localizedCaseInsensitiveContains("denotes that a network service is disabled") else {
                return nil
            }

            if trimmed.hasPrefix("*") {
                let name = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : Service(name: name, isEnabled: false)
            }

            return Service(name: trimmed, isEnabled: true)
        }
    }

    private static func wifiService(in services: [Service]) throws -> String {
        guard let service = services.first(where: { $0.isEnabled && isWiFi($0.name) }) else {
            throw ResolutionError.missingWiFiService
        }
        return service.name
    }

    private static func lanServices(in services: [Service]) -> [String] {
        services.filter { service in
            service.isEnabled && isLAN(service.name)
        }.map(\.name)
    }

    private static func isWiFi(_ name: String) -> Bool {
        let normalized = name.lowercased().replacingOccurrences(of: " ", with: "")
        return normalized == "wi-fi" || normalized == "wifi"
    }

    private static func isLAN(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        guard !lowercased.contains("bridge") else {
            return false
        }
        if lowercased.contains("ethernet") {
            return true
        }
        return name.range(
            of: #"\blan\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
