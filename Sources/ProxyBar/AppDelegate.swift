import AppKit
import ProxyBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let configStore = ConfigStore()
    private let popover = NSPopover()
    private let popoverController = ProxyStatusViewController()
    private var proxyServer: EmbeddedProxyServer?
    private var proxyState = ProxyUIState.off
    private var vpnStatus = VPNStatus.disconnected
    private var vpnRefreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProxyBarDiagnostics.install()
        ProxyBarLog.lifecycle.info("ProxyBar application did finish launching")
        NSApp.setActivationPolicy(.accessory)
        ApplicationMenu.install()
        configurePopover()
        statusItem.button?.image = StatusIcon.make(state: .working)
        statusItem.button?.toolTip = "ProxyBar"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        startProxyServer()
        startVPNStatusMonitoring()
        updateUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProxyBarLog.lifecycle.info("ProxyBar application will terminate")
        vpnRefreshTimer?.invalidate()
        proxyServer?.stop()
    }

    @objc private func addDomain() {
        let alert = NSAlert()
        alert.messageText = "Add Domain"
        alert.informativeText = "Enter a domain or URL. ProxyBar will add the apex and wildcard entries when appropriate."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.placeholderString = "example.com"
        textField.usesSingleLineMode = true
        alert.accessoryView = textField

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = textField
        alert.window.makeFirstResponder(textField)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        performChange {
            _ = try configStore.add(input: textField.stringValue)
        }
    }

    @objc private func applyNow() {
        performChange {
            try configStore.rewriteCurrentDomains()
        }
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configStore.configURL)
    }

    private func toggleLoginItem() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            proxyState = .failed(error.localizedDescription)
        }
        updateUI()
    }

    @objc private func quit() {
        stopProxyServer(disableSystemProxy: true)
        NSApp.terminate(nil)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            refreshVPNStatus()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func performChange(_ change: () throws -> Void) {
        do {
            try change()
            if proxyServer != nil {
                try reloadProxyServer()
                setRunningState()
            } else {
                proxyState = .off
            }
        } catch {
            proxyState = .failed(Self.message(for: error))
        }
        updateUI()
    }

    private func setProxyEnabled(_ enabled: Bool) {
        if enabled {
            startProxyServer()
        } else {
            stopProxyServer(disableSystemProxy: true)
        }
        updateUI()
    }

    private func removeDomain(_ domain: String) {
        performChange {
            _ = try configStore.remove(input: domain)
        }
    }

    private func configurePopover() {
        _ = popoverController.view
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverController

        popoverController.onToggleProxy = { [weak self] enabled in
            self?.setProxyEnabled(enabled)
        }
        popoverController.onAddDomain = { [weak self] in
            self?.addDomain()
        }
        popoverController.onApply = { [weak self] in
            self?.applyNow()
        }
        popoverController.onOpenConfig = { [weak self] in
            self?.openConfig()
        }
        popoverController.onRemoveDomain = { [weak self] domain in
            self?.removeDomain(domain)
        }
        popoverController.onToggleLogin = { [weak self] in
            self?.toggleLoginItem()
        }
        popoverController.onQuit = { [weak self] in
            self?.quit()
        }
    }

    private func startProxyServer() {
        proxyState = .starting
        updateUI()

        do {
            let settings = CrabbyProxyConfigParser.load(from: configStore.configURL)
            let server = EmbeddedProxyServer(settings: settings, enableWireGuardWatcher: true)
            try server.start()
            proxyServer = server
            try SystemActions(settings: settings).apply()
            setRunningState()
            ProxyBarLog.lifecycle.info("ProxyBar proxy server started successfully")
        } catch {
            proxyServer?.stop()
            proxyServer = nil
            proxyState = .failed(Self.message(for: error))
            ProxyBarLog.lifecycle.error("ProxyBar proxy server start failed: \(error.localizedDescription, privacy: .public)")
        }
        updateUI()
    }

    private func stopProxyServer(disableSystemProxy: Bool) {
        proxyState = .stopping
        updateUI()

        proxyServer?.stop()
        proxyServer = nil

        if disableSystemProxy {
            do {
                let settings = CrabbyProxyConfigParser.load(from: configStore.configURL)
                try SystemActions(settings: settings).disableAutoProxy()
                proxyState = .off
            } catch {
                proxyState = .failed(Self.message(for: error))
            }
        } else {
            proxyState = .off
        }
    }

    private func reloadProxyServer() throws {
        let settings = CrabbyProxyConfigParser.load(from: configStore.configURL)

        if let proxyServer {
            try proxyServer.reload(settings: settings)
        } else {
            let server = EmbeddedProxyServer(settings: settings, enableWireGuardWatcher: true)
            try server.start()
            proxyServer = server
        }

        try SystemActions(settings: settings).apply()
        ProxyBarLog.lifecycle.info("ProxyBar proxy settings reloaded successfully")
    }

    private func setRunningState() {
        guard let proxyServer else {
            proxyState = .off
            return
        }
        proxyState = .running(socksPort: proxyServer.boundSOCKSPort, pacPort: proxyServer.boundPACPort)
    }

    private func startVPNStatusMonitoring() {
        refreshVPNStatus()
        vpnRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshVPNStatus()
            }
        }
    }

    private func refreshVPNStatus() {
        vpnStatus = VPNStatus.current()
        updateUI()
    }

    private func updateUI() {
        let status = statusIconState
        statusItem.button?.image = StatusIcon.make(state: status)
        statusItem.button?.toolTip = tooltip
        popoverController.update(with: viewModel(status: status))
    }

    private var statusIconState: StatusIcon.State {
        switch proxyState {
        case .starting, .stopping:
            return .working
        case .running:
            return .running
        case .off:
            return .off
        case .failed:
            return .failed
        }
    }

    private var tooltip: String {
        switch proxyState {
        case .starting:
            return "ProxyBar starting"
        case .running(let socksPort, let pacPort):
            return "ProxyBar running: SOCKS5 \(socksPort), PAC \(pacPort)"
        case .stopping:
            return "ProxyBar stopping"
        case .off:
            return "ProxyBar off"
        case .failed(let message):
            return "ProxyBar error: \(message)"
        }
    }

    private func viewModel(status: StatusIcon.State) -> ProxyStatusViewModel {
        let domains = (try? DomainRules.dedupedAndSorted(configStore.loadDomains())) ?? []

        switch proxyState {
        case .starting:
            return ProxyStatusViewModel(
                title: "Starting ProxyBar",
                detail: "Opening local proxy ports and applying PAC",
                status: status,
                isOn: true,
                socksPort: nil,
                pacPort: nil,
                domainCount: domains.count,
                domains: domains,
                vpnStatus: vpnStatus,
                errorMessage: nil,
                openAtLogin: LoginItem.isEnabled
            )
        case .running(let socksPort, let pacPort):
            return ProxyStatusViewModel(
                title: "Routing Enabled",
                detail: "PAC installed on Wi-Fi at \(Self.shortTime())",
                status: status,
                isOn: true,
                socksPort: socksPort,
                pacPort: pacPort,
                domainCount: domains.count,
                domains: domains,
                vpnStatus: vpnStatus,
                errorMessage: nil,
                openAtLogin: LoginItem.isEnabled
            )
        case .stopping:
            return ProxyStatusViewModel(
                title: "Stopping ProxyBar",
                detail: "Closing listeners and disabling PAC",
                status: status,
                isOn: false,
                socksPort: proxyServer?.boundSOCKSPort,
                pacPort: proxyServer?.boundPACPort,
                domainCount: domains.count,
                domains: domains,
                vpnStatus: vpnStatus,
                errorMessage: nil,
                openAtLogin: LoginItem.isEnabled
            )
        case .off:
            return ProxyStatusViewModel(
                title: "Proxy Off",
                detail: "Local proxy listeners are stopped",
                status: status,
                isOn: false,
                socksPort: nil,
                pacPort: nil,
                domainCount: domains.count,
                domains: domains,
                vpnStatus: vpnStatus,
                errorMessage: nil,
                openAtLogin: LoginItem.isEnabled
            )
        case .failed(let message):
            return ProxyStatusViewModel(
                title: "Proxy Needs Attention",
                detail: "Fix the issue below, then turn ProxyBar on again",
                status: status,
                isOn: false,
                socksPort: proxyServer?.boundSOCKSPort,
                pacPort: proxyServer?.boundPACPort,
                domainCount: domains.count,
                domains: domains,
                vpnStatus: vpnStatus,
                errorMessage: message,
                openAtLogin: LoginItem.isEnabled
            )
        }
    }

    private static func shortTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date())
    }

    private static func message(for error: Error) -> String {
        if let commandFailure = error as? SystemActions.CommandFailure {
            return "Proxy server changed state, but macOS proxy settings could not be updated: \(commandFailure.localizedDescription)"
        }
        return error.localizedDescription
    }

    private enum ProxyUIState {
        case starting
        case running(socksPort: UInt16, pacPort: UInt16)
        case stopping
        case off
        case failed(String)
    }
}
