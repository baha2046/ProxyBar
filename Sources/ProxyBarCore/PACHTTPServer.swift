import Darwin
import Foundation

public final class PACHTTPServer: @unchecked Sendable {
    public private(set) var boundPort: UInt16

    private let contentLock = NSLock()
    private var content: String
    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "ProxyBar.PACHTTPServer")
    private var socketDescriptor: Int32 = -1
    private var isRunning = false

    public init(content: String, port: UInt16) {
        self.content = content
        self.requestedPort = port
        self.boundPort = port
    }

    deinit {
        stop()
    }

    public func update(content: String) {
        contentLock.lock()
        self.content = content
        contentLock.unlock()
    }

    public func start() throws {
        guard !isRunning else {
            return
        }

        let fd: Int32
        do {
            fd = try Self.makeListeningSocket(port: requestedPort)
        } catch let error as POSIXError {
            throw ProxyServerBindError(role: .pac, port: requestedPort, code: error.code)
        }
        socketDescriptor = fd
        boundPort = try Self.boundPort(for: fd)
        isRunning = true
        ProxyBarLog.pac.info("PAC HTTP server listening on 127.0.0.1:\(self.boundPort, privacy: .public)")

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    public func stop() {
        guard socketDescriptor >= 0 else {
            return
        }
        isRunning = false
        Darwin.shutdown(socketDescriptor, SHUT_RDWR)
        Darwin.close(socketDescriptor)
        ProxyBarLog.pac.info("PAC HTTP server stopped")
        socketDescriptor = -1
    }

    private func acceptLoop() {
        while isRunning {
            let client = Darwin.accept(socketDescriptor, nil, nil)
            if client < 0 {
                let error = errno
                if isRunning {
                    ProxyBarLog.pac.error("PAC accept failed: errno=\(error, privacy: .public) \(posixErrorDescription(error), privacy: .public)")
                }
                continue
            }
            Self.disableSIGPIPE(on: client)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handle(client: client)
            }
        }
    }

    private func handle(client: Int32) {
        defer { Darwin.close(client) }
        var buffer = [UInt8](repeating: 0, count: 1024)
        let requestBytes = Darwin.read(client, &buffer, buffer.count)
        if requestBytes < 0 {
            let error = errno
            ProxyBarLog.pac.error("PAC request read failed: errno=\(error, privacy: .public) \(posixErrorDescription(error), privacy: .public)")
        }

        contentLock.lock()
        let body = content
        contentLock.unlock()

        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/x-ns-proxy-autoconfig\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        let written = response.withCString { pointer in
            Darwin.write(client, pointer, strlen(pointer))
        }
        if written < 0 {
            let error = errno
            ProxyBarLog.pac.error("PAC response write failed: errno=\(error, privacy: .public) \(posixErrorDescription(error), privacy: .public)")
        } else {
            ProxyBarLog.pac.debug("PAC response served, request_bytes=\(requestBytes, privacy: .public), response_bytes=\(written, privacy: .public)")
        }
    }

    private static func makeListeningSocket(port: UInt16) throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        disableSIGPIPE(on: fd)

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(fd)
            throw error
        }

        guard Darwin.listen(fd, SOMAXCONN) == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(fd)
            throw error
        }

        return fd
    }

    private static func boundPort(for fd: Int32) throws -> UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fd, $0, &length)
            }
        }
        guard status == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        return UInt16(bigEndian: address.sin_port)
    }

    private static func disableSIGPIPE(on fd: Int32) {
        var value: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
    }
}
