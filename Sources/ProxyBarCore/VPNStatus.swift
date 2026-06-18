import Foundation

public enum VPNStatus: Equatable {
    case connected(name: String)
    case disconnected

    public typealias CommandRunner = (_ executable: String, _ arguments: [String]) throws -> String

    public var isConnected: Bool {
        switch self {
        case .connected:
            return true
        case .disconnected:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .connected(let name):
            return name
        case .disconnected:
            return "Not connected"
        }
    }

    public static func current(commandRunner: CommandRunner = SystemActions.runProcess) -> VPNStatus {
        do {
            let output = try commandRunner("/usr/sbin/scutil", ["--nc", "list"])
            return parseScutilNCList(output)
        } catch {
            return .disconnected
        }
    }

    public static func parseScutilNCList(_ output: String) -> VPNStatus {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.contains("(Connected)"), let name = serviceName(in: String(line)) else {
                continue
            }
            return .connected(name: name)
        }
        return .disconnected
    }

    private static func serviceName(in line: String) -> String? {
        let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
        guard parts.count >= 3 else {
            return nil
        }

        let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
