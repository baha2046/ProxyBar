import Darwin
import Foundation

public final class SOCKS5Server: @unchecked Sendable {
    public private(set) var boundPort: UInt16

    private let settings: ProxySettings
    private let resolver: DoHResolver
    private let queue = DispatchQueue(label: "ProxyBar.SOCKS5Server")
    private let connectionIDLock = NSLock()
    private var socketDescriptor: Int32 = -1
    private var isRunning = false
    private var nextConnectionID: UInt64 = 1

    public init(settings: ProxySettings) {
        self.settings = settings
        self.resolver = DoHResolver(servers: settings.dohServers)
        self.boundPort = settings.socksPort
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard !isRunning else {
            return
        }

        let fd: Int32
        do {
            fd = try Self.makeListeningSocket(port: settings.socksPort)
        } catch let error as POSIXError {
            throw ProxyServerBindError(role: .socks5, port: settings.socksPort, code: error.code)
        }
        socketDescriptor = fd
        boundPort = try Self.boundPort(for: fd)
        isRunning = true
        ProxyBarLog.socks.info("SOCKS5 server listening on 127.0.0.1:\(self.boundPort, privacy: .public)")

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
        ProxyBarLog.socks.info("SOCKS5 server stopped")
        socketDescriptor = -1
    }

    private func acceptLoop() {
        while isRunning {
            let client = Darwin.accept(socketDescriptor, nil, nil)
            if client < 0 {
                let error = errno
                if isRunning {
                    ProxyBarLog.socks.error("SOCKS5 accept failed: errno=\(error, privacy: .public) \(posixErrorDescription(error), privacy: .public)")
                }
                continue
            }
            Self.disableSIGPIPE(on: client)
            Self.enableTCPNoDelay(on: client)
            let connectionID = makeConnectionID()
            let thread = Thread { [weak self] in
                self?.handle(client: client, connectionID: connectionID)
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }

    private func handle(client: Int32, connectionID: UInt64) {
        ProxyBarLog.socks.debug("SOCKS5 #\(connectionID, privacy: .public) accepted")
        defer {
            Darwin.close(client)
            ProxyBarLog.socks.debug("SOCKS5 #\(connectionID, privacy: .public) closed")
        }

        // Bound the handshake so a client that connects but never completes
        // the SOCKS5 negotiation cannot hold a worker thread indefinitely.
        Self.setReadTimeout(on: client, seconds: Self.handshakeTimeoutSeconds)
        let reader = HandshakeReader(fd: client)

        guard let greeting = reader.read(requiredLength: Self.greetingLength),
              greeting.count >= 3,
              greeting[0] == 0x05 else {
            ProxyBarLog.socks.error("SOCKS5 #\(connectionID, privacy: .public) rejected invalid greeting")
            return
        }
        guard writeBytes([0x05, 0x00], to: client) else {
            ProxyBarLog.socks.error("SOCKS5 #\(connectionID, privacy: .public) failed writing greeting response")
            return
        }

        guard let request = reader.read(requiredLength: Self.requestLength),
              request.count >= 7,
              request[0] == 0x05,
              request[1] == 0x01 else {
            ProxyBarLog.socks.error("SOCKS5 #\(connectionID, privacy: .public) rejected unsupported or incomplete request")
            _ = writeBytes([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0], to: client)
            return
        }

        guard let destination = destination(from: request) else {
            ProxyBarLog.socks.error("SOCKS5 #\(connectionID, privacy: .public) rejected malformed destination")
            _ = writeBytes([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0], to: client)
            return
        }
        ProxyBarLog.socks.info("SOCKS5 #\(connectionID, privacy: .public) requested \(destination.host, privacy: .public):\(destination.port, privacy: .public)")

        let remoteHost: String
        if destination.isDomain {
            guard let resolved = resolver.resolveARecord(destination.host) else {
                ProxyBarLog.socks.error("SOCKS5 #\(connectionID, privacy: .public) DNS resolution failed for \(destination.host, privacy: .public)")
                _ = writeBytes([0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0], to: client)
                return
            }
            remoteHost = resolved
            ProxyBarLog.socks.info("SOCKS5 #\(connectionID, privacy: .public) resolved \(destination.host, privacy: .public) to \(remoteHost, privacy: .public)")
        } else {
            remoteHost = destination.host
        }

        let remote = connect(host: remoteHost, port: destination.port)
        guard remote >= 0 else {
            ProxyBarLog.socks.error("SOCKS5 #\(connectionID, privacy: .public) failed connecting to \(remoteHost, privacy: .public):\(destination.port, privacy: .public)")
            _ = writeBytes([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0], to: client)
            return
        }
        defer { Darwin.close(remote) }

        guard writeBytes(successResponse(for: remote), to: client) else {
            ProxyBarLog.socks.error("SOCKS5 #\(connectionID, privacy: .public) failed writing success response")
            return
        }

        // Handshake done: clear the timeout so long-lived idle relays are not
        // torn down, and hand any bytes already buffered to the relay stage.
        Self.setReadTimeout(on: client, seconds: 0)
        relay(
            client,
            remote,
            connectionID: connectionID,
            host: destination.host,
            port: destination.port,
            pendingFromClient: reader.leftover
        )
    }

    private struct Destination {
        var host: String
        var port: UInt16
        var isDomain: Bool
    }

    private func destination(from request: [UInt8]) -> Destination? {
        switch request[3] {
        case 0x01:
            guard request.count >= 10 else {
                return nil
            }
            let host = "\(request[4]).\(request[5]).\(request[6]).\(request[7])"
            let port = UInt16(request[8]) << 8 | UInt16(request[9])
            return Destination(host: host, port: port, isDomain: false)
        case 0x03:
            let length = Int(request[4])
            guard request.count >= 7 + length else {
                return nil
            }
            let hostData = Data(request[5..<(5 + length)])
            guard let host = String(data: hostData, encoding: .utf8) else {
                return nil
            }
            let portIndex = 5 + length
            let port = UInt16(request[portIndex]) << 8 | UInt16(request[portIndex + 1])
            return Destination(host: host, port: port, isDomain: true)
        default:
            return nil
        }
    }

    private func connect(host: String, port: UInt16) -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            let error = errno
            ProxyBarLog.socks.error("SOCKS5 remote socket creation failed: errno=\(error, privacy: .public) \(posixErrorDescription(error), privacy: .public)")
            return -1
        }
        Self.disableSIGPIPE(on: fd)
        Self.enableTCPNoDelay(on: fd)

        if let interfaceIndex = Self.findInterfaceIndex() {
            var index = interfaceIndex
            let status = setsockopt(fd, IPPROTO_IP, 25, &index, socklen_t(MemoryLayout<UInt32>.size))
            if status != 0 {
                let error = errno
                ProxyBarLog.socks.error("SOCKS5 interface binding failed for \(host, privacy: .public): errno=\(error, privacy: .public) \(posixErrorDescription(error), privacy: .public)")
            }
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(host))

        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard status == 0 else {
            let error = errno
            ProxyBarLog.socks.error("SOCKS5 connect failed to \(host, privacy: .public):\(port, privacy: .public): errno=\(error, privacy: .public) \(posixErrorDescription(error), privacy: .public)")
            Darwin.close(fd)
            return -1
        }
        return fd
    }

    private func successResponse(for remote: Int32) -> [UInt8] {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(remote, $0, &length)
            }
        }
        guard status == 0 else {
            return [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
        }

        var response: [UInt8] = [0x05, 0x00, 0x00, 0x01]
        withUnsafeBytes(of: address.sin_addr.s_addr) { bytes in
            response.append(contentsOf: bytes)
        }
        withUnsafeBytes(of: address.sin_port) { bytes in
            response.append(contentsOf: bytes)
        }
        return response
    }

    private func relay(
        _ client: Int32,
        _ remote: Int32,
        connectionID: UInt64,
        host: String,
        port: UInt16,
        pendingFromClient: [UInt8]
    ) {
        let clientToRemote = RelayResultBox()
        let done = DispatchSemaphore(value: 0)

        // Pump client -> remote on a dedicated thread so this connection never
        // depends on the shared GCD worker pool (which has a hard thread cap and
        // starves under bursts of concurrent connections).
        let pump = Thread { [weak self] in
            var result = RelayResult()
            if !pendingFromClient.isEmpty {
                if self?.writeBytes(pendingFromClient, to: remote) == true {
                    result.bytes += pendingFromClient.count
                } else {
                    result.writeError = errno
                }
            }
            if result.writeError == nil {
                let copied = Self.copy(from: client, to: remote)
                result.bytes += copied.bytes
                result.readError = copied.readError
                result.writeError = copied.writeError
            }
            clientToRemote.result = result
            Darwin.shutdown(remote, SHUT_WR)
            done.signal()
        }
        pump.stackSize = 512 * 1024
        pump.start()

        let remoteToClient = Self.copy(from: remote, to: client)
        Darwin.shutdown(client, SHUT_WR)
        done.wait()

        logRelayCompletion(
            connectionID: connectionID,
            host: host,
            port: port,
            clientToRemote: clientToRemote.result,
            remoteToClient: remoteToClient
        )
    }

    private static func copy(from source: Int32, to destination: Int32) -> RelayResult {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        var result = RelayResult()
        while true {
            let count = Darwin.read(source, &buffer, buffer.count)
            if count == 0 {
                return result
            }
            guard count > 0 else {
                result.readError = errno
                return result
            }
            var written = 0
            while written < count {
                let n = buffer.withUnsafeBytes { rawBuffer in
                    Darwin.write(destination, rawBuffer.baseAddress!.advanced(by: written), count - written)
                }
                guard n > 0 else {
                    result.writeError = errno
                    return result
                }
                written += n
                result.bytes += n
            }
        }
    }

    /// Maximum seconds a client may take to complete the SOCKS5 handshake.
    private static let handshakeTimeoutSeconds = 30

    /// Required total length of a SOCKS5 greeting `[VER, NMETHODS, METHODS...]`.
    /// Returns nil while the header is incomplete so the reader keeps reading.
    private static func greetingLength(_ buffer: [UInt8]) -> Int? {
        guard buffer.count >= 2 else { return nil }
        guard buffer[0] == 0x05 else { return buffer.count }
        return 2 + Int(buffer[1])
    }

    /// Required total length of a SOCKS5 request, derived from its address type.
    /// Returns nil while not enough bytes have arrived to determine the length.
    private static func requestLength(_ buffer: [UInt8]) -> Int? {
        guard buffer.count >= 4 else { return nil }
        switch buffer[3] {
        case 0x01: // IPv4: VER CMD RSV ATYP + 4 addr + 2 port
            return 10
        case 0x03: // domain: VER CMD RSV ATYP + 1 len + len + 2 port
            guard buffer.count >= 5 else { return nil }
            return 7 + Int(buffer[4])
        case 0x04: // IPv6: VER CMD RSV ATYP + 16 addr + 2 port
            return 22
        default:
            return buffer.count
        }
    }

    /// Reads framed SOCKS5 messages from a socket, accumulating bytes across
    /// multiple `read()` calls until a complete message is available. Any bytes
    /// beyond the current message are retained for the next read (or relayed).
    private final class HandshakeReader {
        private let fd: Int32
        private(set) var leftover: [UInt8] = []

        init(fd: Int32) {
            self.fd = fd
        }

        /// Reads until `requiredLength(buffer)` is satisfied, returns exactly
        /// that many bytes, and keeps the remainder in `leftover`.
        func read(requiredLength: ([UInt8]) -> Int?) -> [UInt8]? {
            var chunk = [UInt8](repeating: 0, count: 512)
            while true {
                if let required = requiredLength(leftover), leftover.count >= required {
                    let message = Array(leftover.prefix(required))
                    leftover.removeFirst(required)
                    return message
                }
                // Guard against an unbounded handshake from a hostile client.
                guard leftover.count < 4096 else {
                    return nil
                }
                let count = Darwin.read(fd, &chunk, chunk.count)
                guard count > 0 else {
                    if count < 0 {
                        let error = errno
                        ProxyBarLog.socks.error("SOCKS5 read failed: errno=\(error, privacy: .public) \(posixErrorDescription(error), privacy: .public)")
                    }
                    return nil
                }
                leftover.append(contentsOf: chunk[0..<count])
            }
        }
    }

    @discardableResult
    private func writeBytes(_ bytes: [UInt8], to fd: Int32) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeBytes { rawBuffer in
                Darwin.write(fd, rawBuffer.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            guard count > 0 else {
                let error = errno
                ProxyBarLog.socks.error("SOCKS5 write failed: errno=\(error, privacy: .public) \(posixErrorDescription(error), privacy: .public)")
                return false
            }
            offset += count
        }
        return true
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

    private func makeConnectionID() -> UInt64 {
        connectionIDLock.lock()
        defer { connectionIDLock.unlock() }
        let id = nextConnectionID
        nextConnectionID += 1
        return id
    }

    private struct RelayResult {
        var bytes = 0
        var readError: Int32?
        var writeError: Int32?
    }

    private final class RelayResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = RelayResult()

        var result: RelayResult {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
            set {
                lock.lock()
                storage = newValue
                lock.unlock()
            }
        }
    }

    private func logRelayCompletion(
        connectionID: UInt64,
        host: String,
        port: UInt16,
        clientToRemote: RelayResult,
        remoteToClient: RelayResult
    ) {
        let clientReadError = clientToRemote.readError.map(posixErrorDescription) ?? "none"
        let clientWriteError = clientToRemote.writeError.map(posixErrorDescription) ?? "none"
        let remoteReadError = remoteToClient.readError.map(posixErrorDescription) ?? "none"
        let remoteWriteError = remoteToClient.writeError.map(posixErrorDescription) ?? "none"

        ProxyBarLog.socks.info(
            """
            SOCKS5 #\(connectionID, privacy: .public) relay finished for \(host, privacy: .public):\(port, privacy: .public), \
            c2r_bytes=\(clientToRemote.bytes, privacy: .public), r2c_bytes=\(remoteToClient.bytes, privacy: .public), \
            c2r_read_error=\(clientReadError, privacy: .public), c2r_write_error=\(clientWriteError, privacy: .public), \
            r2c_read_error=\(remoteReadError, privacy: .public), r2c_write_error=\(remoteWriteError, privacy: .public)
            """
        )
    }

    private static func disableSIGPIPE(on fd: Int32) {
        var value: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func enableTCPNoDelay(on fd: Int32) {
        var value: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Sets the receive timeout for a socket. Passing 0 clears the timeout
    /// (the socket blocks indefinitely again).
    private static func setReadTimeout(on fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
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

    private static func findInterfaceIndex() -> UInt32? {
        for name in ["en0", "en6", "en1"] {
            let index = if_nametoindex(name)
            if index != 0 {
                return index
            }
        }
        return nil
    }
}
