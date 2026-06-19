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

    public struct OrderedService: Equatable, Sendable {
        public let name: String
        public let hardwarePort: String
        public let device: String
        public let isEnabled: Bool

        public init(name: String, hardwarePort: String, device: String, isEnabled: Bool) {
            self.name = name
            self.hardwarePort = hardwarePort
            self.device = device
            self.isEnabled = isEnabled
        }
    }

    public enum ResolutionError: Error, LocalizedError, Equatable {
        case missingWiFiService
        case missingLANService
        case missingDefaultRouteInterface
        case missingActiveService(String)

        public var errorDescription: String? {
            switch self {
            case .missingWiFiService:
                return "Wi-Fi network service not found."
            case .missingLANService:
                return "LAN network service not found."
            case .missingDefaultRouteInterface:
                return "Active network interface not found."
            case .missingActiveService(let interface):
                return "Active network service not found for interface \(interface)."
            }
        }
    }

    public static func resolveActiveService(
        commandRunner: SystemActions.CommandRunner = SystemActions.runProcess
    ) throws -> String {
        let defaultRouteOutput = try commandRunner("/sbin/route", ["-n", "get", "default"])
        let networkServiceOrderOutput = try commandRunner("/usr/sbin/networksetup", ["-listnetworkserviceorder"])
        return try resolveActiveService(
            defaultRouteOutput: defaultRouteOutput,
            networkServiceOrderOutput: networkServiceOrderOutput
        )
    }

    public static func resolveActiveService(
        defaultRouteOutput: String,
        networkServiceOrderOutput: String
    ) throws -> String {
        guard let interface = parseDefaultRouteInterface(defaultRouteOutput) else {
            throw ResolutionError.missingDefaultRouteInterface
        }
        guard let service = parseNetworkServiceOrder(networkServiceOrderOutput).first(where: {
            $0.isEnabled && $0.device == interface
        }) else {
            throw ResolutionError.missingActiveService(interface)
        }
        return service.name
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

    public static func parseDefaultRouteInterface(_ output: String) -> String? {
        for rawLine in output.components(separatedBy: .newlines) {
            let parts = rawLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == "interface" else {
                continue
            }
            let interface = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return interface.isEmpty ? nil : interface
        }
        return nil
    }

    public static func parseNetworkServiceOrder(_ output: String) -> [OrderedService] {
        let servicePattern = #"^\(\d+\)\s+(.+)$"#
        let detailPattern = #"^\(Hardware Port:\s*(.+),\s*Device:\s*([^)]+)\)$"#
        var pendingService: (name: String, isEnabled: Bool)?
        var services: [OrderedService] = []

        for rawLine in output.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.localizedCaseInsensitiveContains("denotes that a network service is disabled") else {
                continue
            }

            if let match = trimmed.firstMatch(pattern: servicePattern) {
                var name = String(trimmed[match.range(at: 1)])
                var isEnabled = true
                if name.hasPrefix("*") {
                    name = String(name.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                    isEnabled = false
                }
                pendingService = name.isEmpty ? nil : (name, isEnabled)
                continue
            }

            if let pending = pendingService,
               let match = trimmed.firstMatch(pattern: detailPattern) {
                services.append(OrderedService(
                    name: pending.name,
                    hardwarePort: String(trimmed[match.range(at: 1)]).trimmingCharacters(in: .whitespacesAndNewlines),
                    device: String(trimmed[match.range(at: 2)]).trimmingCharacters(in: .whitespacesAndNewlines),
                    isEnabled: pending.isEnabled
                ))
                pendingService = nil
            }
        }

        return services
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

private extension String {
    func firstMatch(pattern: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        return regex.firstMatch(in: self, range: NSRange(startIndex..., in: self))
    }

    subscript(range: NSRange) -> Substring {
        self[Range(range, in: self)!]
    }
}
