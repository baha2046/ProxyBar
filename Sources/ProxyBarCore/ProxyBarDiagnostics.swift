import Darwin
import Foundation
import OSLog

public enum ProxyBarLog {
    public static let lifecycle = Logger(subsystem: "ProxyBar", category: "lifecycle")
    public static let socks = Logger(subsystem: "ProxyBar", category: "socks5")
    public static let pac = Logger(subsystem: "ProxyBar", category: "pac")
    public static let doh = Logger(subsystem: "ProxyBar", category: "doh")
}

public enum ProxyBarDiagnostics {
    public static func install() {
        signal(SIGPIPE, SIG_IGN)
        ProxyBarLog.lifecycle.info("ProxyBar diagnostics installed; SIGPIPE will be reported as socket write errors")
    }
}

func posixErrorDescription(_ code: Int32) -> String {
    String(cString: strerror(code))
}
