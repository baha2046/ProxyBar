import Darwin
import Foundation

public final class SOCKS5Server: @unchecked Sendable {
    public private(set) var boundPort: UInt16

    private let settings: ProxySettings
    private let resolver: DoHResolver
    private let queue = DispatchQueue(label: "ProxyBar.SOCKS5Server")
    private var socketDescriptor: Int32 = -1
    private var isRunning = false

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

        let fd = try Self.makeListeningSocket(port: settings.socksPort)
        socketDescriptor = fd
        boundPort = try Self.boundPort(for: fd)
        isRunning = true

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
        socketDescriptor = -1
    }

    private func acceptLoop() {
        while isRunning {
            let client = Darwin.accept(socketDescriptor, nil, nil)
            if client < 0 {
                continue
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(client: client)
            }
        }
    }

    private func handle(client: Int32) {
        defer { Darwin.close(client) }

        guard let greeting = readBytes(from: client, maxCount: 512),
              greeting.count >= 3,
              greeting[0] == 0x05 else {
            return
        }
        guard writeBytes([0x05, 0x00], to: client) else {
            return
        }

        guard let request = readBytes(from: client, maxCount: 512),
              request.count >= 7,
              request[0] == 0x05,
              request[1] == 0x01 else {
            _ = writeBytes([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0], to: client)
            return
        }

        guard let destination = destination(from: request) else {
            _ = writeBytes([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0], to: client)
            return
        }

        let remoteHost: String
        if destination.isDomain {
            guard let resolved = resolver.resolveARecord(destination.host) else {
                _ = writeBytes([0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0], to: client)
                return
            }
            remoteHost = resolved
        } else {
            remoteHost = destination.host
        }

        let remote = connect(host: remoteHost, port: destination.port)
        guard remote >= 0 else {
            _ = writeBytes([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0], to: client)
            return
        }
        defer { Darwin.close(remote) }

        guard writeBytes(successResponse(for: remote), to: client) else {
            return
        }

        relay(client, remote)
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
            return -1
        }

        if let interfaceIndex = Self.findInterfaceIndex() {
            var index = interfaceIndex
            setsockopt(fd, IPPROTO_IP, 25, &index, socklen_t(MemoryLayout<UInt32>.size))
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

    private func relay(_ left: Int32, _ right: Int32) {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            Self.copy(from: left, to: right)
            Darwin.shutdown(right, SHUT_WR)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            Self.copy(from: right, to: left)
            Darwin.shutdown(left, SHUT_WR)
            group.leave()
        }
        group.wait()
    }

    private static func copy(from source: Int32, to destination: Int32) {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = Darwin.read(source, &buffer, buffer.count)
            guard count > 0 else {
                return
            }
            var written = 0
            while written < count {
                let n = buffer.withUnsafeBytes { rawBuffer in
                    Darwin.write(destination, rawBuffer.baseAddress!.advanced(by: written), count - written)
                }
                guard n > 0 else {
                    return
                }
                written += n
            }
        }
    }

    private func readBytes(from fd: Int32, maxCount: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: maxCount)
        let count = Darwin.read(fd, &buffer, maxCount)
        guard count > 0 else {
            return nil
        }
        return Array(buffer.prefix(count))
    }

    @discardableResult
    private func writeBytes(_ bytes: [UInt8], to fd: Int32) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeBytes { rawBuffer in
                Darwin.write(fd, rawBuffer.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            guard count > 0 else {
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
