import Foundation

public final class EmbeddedProxyServer: @unchecked Sendable {
    public private(set) var settings: ProxySettings
    public private(set) var boundPACPort: UInt16 = 0
    public private(set) var boundSOCKSPort: UInt16 = 0
    public let requestActivity: RequestActivityTimeline

    private let enableWireGuardWatcher: Bool
    private var pacServer: PACHTTPServer?
    private var socksServer: SOCKS5Server?
    private var wireGuardWatcher: WireGuardProxyWatcher?
    private let lock = NSLock()

    public init(
        settings: ProxySettings,
        enableWireGuardWatcher: Bool = false,
        requestActivity: RequestActivityTimeline = RequestActivityTimeline()
    ) {
        self.settings = settings
        self.enableWireGuardWatcher = enableWireGuardWatcher
        self.requestActivity = requestActivity
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard pacServer == nil, socksServer == nil else {
            ProxyBarLog.lifecycle.debug("Embedded proxy start skipped because servers are already running")
            return
        }
        try startLocked(settings: settings)
    }

    public func reload(settings newSettings: ProxySettings) throws {
        lock.lock()
        defer { lock.unlock() }

        guard pacServer != nil, socksServer != nil else {
            settings = newSettings
            try startLocked(settings: newSettings)
            return
        }

        let pacPortMatches = newSettings.pacPort == settings.pacPort || newSettings.pacPort == boundPACPort
        let socksPortMatches = newSettings.socksPort == settings.socksPort || newSettings.socksPort == boundSOCKSPort
        let socksCanStayRunning = socksPortMatches && newSettings.dohServers == settings.dohServers

        if pacPortMatches && socksCanStayRunning {
            settings = newSettings
            pacServer?.update(content: PACGenerator.generate(domains: newSettings.domains, socksPort: boundSOCKSPort))
            ProxyBarLog.lifecycle.info("Embedded proxy reloaded PAC content without restarting servers")
            return
        }

        ProxyBarLog.lifecycle.info("Embedded proxy restarting for settings reload")
        stopLocked()
        settings = newSettings
        try startLocked(settings: newSettings)
    }

    public func stop() {
        lock.lock()
        stopLocked()
        lock.unlock()
    }

    private func startLocked(settings: ProxySettings) throws {
        ProxyBarLog.lifecycle.info("Starting embedded proxy servers with requested SOCKS5 port \(settings.socksPort, privacy: .public), PAC port \(settings.pacPort, privacy: .public)")
        let socks = SOCKS5Server(settings: settings, requestActivity: requestActivity)
        try socks.start()

        let pac = PACHTTPServer(
            content: PACGenerator.generate(domains: settings.domains, socksPort: socks.boundPort),
            port: settings.pacPort
        )

        do {
            try pac.start()
        } catch {
            socks.stop()
            throw error
        }

        socksServer = socks
        pacServer = pac
        boundSOCKSPort = socks.boundPort
        boundPACPort = pac.boundPort
        ProxyBarLog.lifecycle.info("Embedded proxy started with SOCKS5 port \(self.boundSOCKSPort, privacy: .public), PAC port \(self.boundPACPort, privacy: .public)")

        if enableWireGuardWatcher {
            let watcher = WireGuardProxyWatcher()
            watcher.start()
            wireGuardWatcher = watcher
            ProxyBarLog.lifecycle.info("WireGuard proxy watcher started")
        }
    }

    private func stopLocked() {
        ProxyBarLog.lifecycle.info("Stopping embedded proxy servers")
        wireGuardWatcher?.stop()
        wireGuardWatcher = nil
        pacServer?.stop()
        pacServer = nil
        socksServer?.stop()
        socksServer = nil
        boundPACPort = 0
        boundSOCKSPort = 0
    }
}

final class WireGuardProxyWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ProxyBar.WireGuardProxyWatcher")
    private var timer: DispatchSourceTimer?
    private var lastWasVPN = false

    func start() {
        guard timer == nil else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let primary = Self.primaryInterface() ?? ""
        let isVPN = primary.hasPrefix("utun")
        if isVPN && !lastWasVPN {
            Self.setPACWithHelperIfAvailable()
        }
        lastWasVPN = isVPN
    }

    private static func primaryInterface() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            input.fileHandleForWriting.write(Data("open\nshow State:/Network/Global/IPv4\nquit\n".utf8))
            input.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = trimmed.removingPrefix("PrimaryInterface :") {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func setPACWithHelperIfAvailable() {
        guard let helper = setPACHelperURL() else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = [helper.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private static func setPACHelperURL() -> URL? {
        let fileManager = FileManager.default

        if let executable = Bundle.main.executableURL {
            let candidate = executable.deletingLastPathComponent().appendingPathComponent("crabbyproxy-setpac")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let homeCandidate = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local")
            .appendingPathComponent("bin")
            .appendingPathComponent("crabbyproxy-setpac")
        if fileManager.fileExists(atPath: homeCandidate.path) {
            return homeCandidate
        }

        return nil
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}
