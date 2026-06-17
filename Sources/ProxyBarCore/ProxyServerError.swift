import Foundation

public enum ProxyServerRole: String, Sendable {
    case socks5 = "SOCKS5"
    case pac = "PAC"

    var configKey: String {
        switch self {
        case .socks5:
            return "socks_port"
        case .pac:
            return "pac_port"
        }
    }
}

public struct ProxyServerBindError: Error, LocalizedError, Sendable {
    public let role: ProxyServerRole
    public let port: UInt16
    public let code: POSIXErrorCode

    public var errorDescription: String? {
        if code == .EADDRINUSE {
            return "\(role.rawValue) port \(port) is already in use. Quit the other app or change \(role.configKey) in config.toml."
        }
        return "\(role.rawValue) port \(port) could not be opened: \(posixErrorDescription(code.rawValue))."
    }
}
