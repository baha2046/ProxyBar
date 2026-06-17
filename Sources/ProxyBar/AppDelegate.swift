import AppKit
import ProxyBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let configStore = ConfigStore()
    private var proxyServer: EmbeddedProxyServer?
    private var statusMessage = "Ready"

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProxyBarDiagnostics.install()
        ProxyBarLog.lifecycle.info("ProxyBar application did finish launching")
        NSApp.setActivationPolicy(.accessory)
        ApplicationMenu.install()
        statusItem.button?.image = StatusIcon.make()
        statusItem.button?.toolTip = "ProxyBar"
        startProxyServer()
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProxyBarLog.lifecycle.info("ProxyBar application will terminate")
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

    @objc private func removeDomain(_ sender: NSMenuItem) {
        guard let domain = sender.representedObject as? String else {
            return
        }

        performChange {
            _ = try configStore.remove(input: domain)
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

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            try LoginItem.setEnabled(sender.state != .on)
            statusMessage = LoginItem.isEnabled ? "Open at Login enabled" : "Open at Login disabled"
        } catch {
            statusMessage = error.localizedDescription
        }
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func performChange(_ change: () throws -> Void) {
        do {
            try change()
            try reloadProxyServer()
            statusMessage = "Applied at \(Self.shortTime())"
        } catch {
            statusMessage = error.localizedDescription
        }
        rebuildMenu()
    }

    private func startProxyServer() {
        do {
            let settings = CrabbyProxyConfigParser.load(from: configStore.configURL)
            let server = EmbeddedProxyServer(settings: settings, enableWireGuardWatcher: true)
            try server.start()
            proxyServer = server
            try SystemActions(settings: settings).apply()
            statusMessage = "Proxy listening on SOCKS5 \(server.boundSOCKSPort), PAC \(server.boundPACPort)"
            ProxyBarLog.lifecycle.info("ProxyBar proxy server started successfully")
        } catch {
            statusMessage = error.localizedDescription
            ProxyBarLog.lifecycle.error("ProxyBar proxy server start failed: \(error.localizedDescription, privacy: .public)")
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

    private func rebuildMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusMessage, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Add Domain...", action: #selector(addDomain), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Apply Now", action: #selector(applyNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: "o"))
        menu.addItem(.separator())

        addDomains(to: menu)

        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func addDomains(to menu: NSMenu) {
        let title = NSMenuItem(title: "Domains", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        do {
            let domains = DomainRules.dedupedAndSorted(try configStore.loadDomains())
            if domains.isEmpty {
                let empty = NSMenuItem(title: "No domains configured", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
                return
            }

            for domain in domains {
                let item = NSMenuItem(title: "Remove \(domain)", action: #selector(removeDomain(_:)), keyEquivalent: "")
                item.representedObject = domain
                menu.addItem(item)
            }
        } catch {
            let errorItem = NSMenuItem(title: error.localizedDescription, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }
    }

    private static func shortTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date())
    }
}
