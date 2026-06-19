import AppKit
import ProxyBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let configStore = ConfigStore()
    private let popover = NSPopover()
    private let popoverController = ProxyStatusViewController()
    private let settingsWindowController = SettingsWindowController()
    private let requestActivity = RequestActivityTimeline()
    private var proxyServer: EmbeddedProxyServer?
    private var proxyState = ProxyUIState.off
    private var vpnStatus = VPNStatus.disconnected
    private var vpnRefreshTimer: Timer?
    private var proxyNetworkScope = AppPreferences.proxyNetworkScope

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
        // Seed VPN status before starting the proxy so the initial routing
        // decision (run vs. standby) reflects the live VPN state.
        vpnStatus = VPNStatus.current()
        startProxyServer()
        startVPNStatusMonitoring()
        updateUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProxyBarLog.lifecycle.info("ProxyBar application will terminate")
        vpnRefreshTimer?.invalidate()
        proxyServer?.stop()
        requestActivity.reset()
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

    @objc private func openSettings() {
        settingsWindowController.update(scope: proxyNetworkScope, openAtLogin: LoginItem.isEnabled)
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleLoginItem() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            proxyState = .failed(error.localizedDescription)
        }
        settingsWindowController.update(scope: proxyNetworkScope, openAtLogin: LoginItem.isEnabled)
        updateUI()
    }

    private func setProxyNetworkScope(_ scope: ProxyNetworkScope) {
        guard scope != proxyNetworkScope else {
            return
        }

        let previousScope = proxyNetworkScope
        proxyNetworkScope = scope
        AppPreferences.proxyNetworkScope = scope

        guard proxyServer != nil else {
            updateUI()
            return
        }

        do {
            let settings = CrabbyProxyConfigParser.load(from: configStore.configURL)
            try SystemActions(settings: settings, networkServices: networkServices(for: previousScope)).disableAutoProxy()
            establishRouting()
        } catch {
            proxyState = .failed(Self.message(for: error))
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
                establishRouting()
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
        popoverController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        popoverController.onRemoveDomain = { [weak self] domain in
            self?.removeDomain(domain)
        }
        popoverController.onQuit = { [weak self] in
            self?.quit()
        }

        settingsWindowController.onScopeChange = { [weak self] scope in
            self?.setProxyNetworkScope(scope)
        }
        settingsWindowController.onToggleLogin = { [weak self] in
            self?.toggleLoginItem()
        }
    }

    private func startProxyServer() {
        proxyState = .starting
        updateUI()

        do {
            let settings = CrabbyProxyConfigParser.load(from: configStore.configURL)
            requestActivity.reset()
            let server = EmbeddedProxyServer(
                settings: settings,
                enableWireGuardWatcher: true,
                requestActivity: requestActivity
            )
            try server.start()
            proxyServer = server
            establishRouting()
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
        requestActivity.reset()

        if disableSystemProxy {
            do {
                let settings = CrabbyProxyConfigParser.load(from: configStore.configURL)
                try SystemActions(settings: settings, networkServices: networkServices(for: proxyNetworkScope)).disableAutoProxy()
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
            let server = EmbeddedProxyServer(
                settings: settings,
                enableWireGuardWatcher: true,
                requestActivity: requestActivity
            )
            try server.start()
            proxyServer = server
        }

        // PAC state is reconciled by establishRouting() based on the current VPN
        // status, so it is intentionally not applied here.
        ProxyBarLog.lifecycle.info("ProxyBar proxy settings reloaded successfully")
    }

    /// The proxy server is up — sync the system PAC to the current VPN status
    /// and set the matching UI state. When the VPN is connected, PAC is applied
    /// and routing is active (`.running`). When the VPN is offline, PAC is
    /// disabled and routing sits in `.standby` until the VPN returns.
    private func establishRouting() {
        guard let proxyServer else {
            proxyState = .off
            return
        }

        let settings = CrabbyProxyConfigParser.load(from: configStore.configURL)
        let socksPort = proxyServer.boundSOCKSPort
        let pacPort = proxyServer.boundPACPort

        do {
            let actions = SystemActions(settings: settings, networkServices: try networkServices(for: proxyNetworkScope))
            if vpnStatus.isConnected {
                try actions.apply()
                proxyState = .running(socksPort: socksPort, pacPort: pacPort)
                ProxyBarLog.lifecycle.info("ProxyBar routing enabled (VPN connected)")
            } else {
                try actions.disableAutoProxy()
                proxyState = .standby(socksPort: socksPort, pacPort: pacPort)
                ProxyBarLog.lifecycle.info("ProxyBar entering standby (VPN offline, PAC disabled)")
            }
        } catch {
            proxyState = .failed(Self.message(for: error))
            ProxyBarLog.lifecycle.error("ProxyBar routing sync failed: \(error.localizedDescription, privacy: .public)")
        }
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
        let previous = vpnStatus
        vpnStatus = VPNStatus.current()

        // When routing is active or standing by, a VPN change must reconcile the
        // system PAC: offline → standby (PAC off), online → running (PAC on).
        if let proxyServer, case .running = proxyState, !vpnStatus.isConnected {
            ProxyBarLog.lifecycle.info("VPN disconnected while routing — entering standby")
            let socksPort = proxyServer.boundSOCKSPort
            let pacPort = proxyServer.boundPACPort
            disablePACQuietly()
            proxyState = .standby(socksPort: socksPort, pacPort: pacPort)
        } else if case .standby = proxyState, vpnStatus.isConnected {
            ProxyBarLog.lifecycle.info("VPN connected while standing by — resuming routing")
            establishRouting()
        }

        if previous != vpnStatus {
            ProxyBarLog.lifecycle.info("VPN status changed: \(previous.displayName) → \(self.vpnStatus.displayName)")
        }
        updateUI()
    }

    private func disablePACQuietly() {
        let settings = CrabbyProxyConfigParser.load(from: configStore.configURL)
        do {
            try SystemActions(settings: settings, networkServices: networkServices(for: proxyNetworkScope)).disableAutoProxy()
        } catch {
            ProxyBarLog.lifecycle.error("Failed to disable PAC while entering standby: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func networkServices(for scope: ProxyNetworkScope) throws -> [String] {
        try NetworkServiceResolver.resolve(scope: scope)
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
        case .standby:
            return .standby
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
        case .standby(let socksPort, let pacPort):
            return "ProxyBar standby: VPN offline (SOCKS5 \(socksPort), PAC \(pacPort) disabled)"
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
        let requestCounts = proxyServer == nil ? Array(repeating: 0, count: requestActivity.bucketCount) : requestActivity.counts()

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
                requestCountsPerMinute: requestCounts,
                vpnStatus: vpnStatus,
                errorMessage: nil
            )
        case .running(let socksPort, let pacPort):
            return ProxyStatusViewModel(
                title: "Routing Enabled",
                detail: "PAC installed on \(proxyNetworkScope.displayName) at \(Self.shortTime())",
                status: status,
                isOn: true,
                socksPort: socksPort,
                pacPort: pacPort,
                domainCount: domains.count,
                domains: domains,
                requestCountsPerMinute: requestCounts,
                vpnStatus: vpnStatus,
                errorMessage: nil
            )
        case .standby(let socksPort, let pacPort):
            return ProxyStatusViewModel(
                title: "Standby",
                detail: "VPN offline — PAC disabled for \(proxyNetworkScope.displayName)",
                status: status,
                isOn: true,
                socksPort: socksPort,
                pacPort: pacPort,
                domainCount: domains.count,
                domains: domains,
                requestCountsPerMinute: requestCounts,
                vpnStatus: vpnStatus,
                errorMessage: nil
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
                requestCountsPerMinute: requestCounts,
                vpnStatus: vpnStatus,
                errorMessage: nil
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
                requestCountsPerMinute: requestCounts,
                vpnStatus: vpnStatus,
                errorMessage: nil
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
                requestCountsPerMinute: requestCounts,
                vpnStatus: vpnStatus,
                errorMessage: message
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
        case standby(socksPort: UInt16, pacPort: UInt16)
        case stopping
        case off
        case failed(String)
    }
}
