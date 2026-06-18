import Darwin
import Foundation

public struct SystemActions {
    public typealias CommandRunner = (_ executable: String, _ arguments: [String]) throws -> String

    public struct CommandFailure: Error, LocalizedError {
        public let command: String
        public let status: Int32
        public let output: String

        public var errorDescription: String? {
            let details = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "\(command) failed with exit code \(status)."
            }
            return "\(command) failed with exit code \(status): \(details)"
        }
    }

    public let networkServices: [String]
    public let pacURL: String
    private let commandRunner: CommandRunner

    public var networkService: String {
        networkServices.first ?? "Wi-Fi"
    }

    public init(
        networkService: String = "Wi-Fi",
        pacURL: String = "http://127.0.0.1:1081/proxy.pac",
        commandRunner: @escaping CommandRunner = SystemActions.runProcess
    ) {
        self.init(networkServices: [networkService], pacURL: pacURL, commandRunner: commandRunner)
    }

    public init(
        networkServices: [String],
        pacURL: String = "http://127.0.0.1:1081/proxy.pac",
        commandRunner: @escaping CommandRunner = SystemActions.runProcess
    ) {
        self.networkServices = networkServices.isEmpty ? ["Wi-Fi"] : networkServices
        self.pacURL = pacURL
        self.commandRunner = commandRunner
    }

    public init(
        settings: ProxySettings,
        networkService: String = "Wi-Fi",
        commandRunner: @escaping CommandRunner = SystemActions.runProcess
    ) {
        self.init(networkService: networkService, pacURL: settings.pacURL, commandRunner: commandRunner)
    }

    public init(
        settings: ProxySettings,
        networkServices: [String],
        commandRunner: @escaping CommandRunner = SystemActions.runProcess
    ) {
        self.init(networkServices: networkServices, pacURL: settings.pacURL, commandRunner: commandRunner)
    }

    public func apply() throws {
        try refreshPAC()
    }

    public func restartService() throws {
        try apply()
    }

    public func refreshPAC() throws {
        for service in networkServices {
            try run(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", service, "off"]
            )
            try run(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxyurl", service, pacURL]
            )
            try run(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", service, "on"]
            )
        }
    }

    public func disableAutoProxy() throws {
        for service in networkServices {
            try run(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", service, "off"]
            )
        }
    }

    @discardableResult
    private func run(executable: String, arguments: [String]) throws -> String {
        try commandRunner(executable, arguments)
    }

    @discardableResult
    public static func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw CommandFailure(
                command: ([executable] + arguments).joined(separator: " "),
                status: process.terminationStatus,
                output: output
            )
        }
        return output
    }
}

public enum ProxyNetworkScope: String, CaseIterable, Equatable, Sendable {
    case wifi
    case lan
    case both

    public var title: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .lan:
            return "LAN"
        case .both:
            return "Both"
        }
    }

    public var displayName: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .lan:
            return "LAN"
        case .both:
            return "Wi-Fi and LAN"
        }
    }
}
