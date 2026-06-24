import AppKit
import ProxyBarCore

@MainActor
final class SettingsWindowController: NSWindowController {
    var onScopeChange: ((ProxyNetworkScope) -> Void)?
    var onRoutingModeChange: ((DomainRoutingMode) -> Void)?
    var onToggleLogin: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    private let settingsViewController = SettingsViewController()

    init() {
        let window = NSWindow(contentViewController: settingsViewController)
        window.title = "ProxyBar Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        settingsViewController.onScopeChange = { [weak self] scope in
            self?.onScopeChange?(scope)
        }
        settingsViewController.onRoutingModeChange = { [weak self] mode in
            self?.onRoutingModeChange?(mode)
        }
        settingsViewController.onToggleLogin = { [weak self] in
            self?.onToggleLogin?()
        }
        settingsViewController.onCheckForUpdates = { [weak self] in
            self?.onCheckForUpdates?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(scope: ProxyNetworkScope, routingMode: DomainRoutingMode, openAtLogin: Bool) {
        settingsViewController.update(scope: scope, routingMode: routingMode, openAtLogin: openAtLogin)
    }
}

@MainActor
private final class SettingsViewController: NSViewController {
    var onScopeChange: ((ProxyNetworkScope) -> Void)?
    var onRoutingModeChange: ((DomainRoutingMode) -> Void)?
    var onToggleLogin: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    private let scopeControl = NSSegmentedControl(labels: ProxyNetworkScope.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let routingModeControl = NSSegmentedControl(labels: DomainRoutingMode.allCases.map(\.settingsTitle), trackingMode: .selectOne, target: nil, action: nil)
    private let loginSwitch = NSSwitch()
    private let versionLabel = NSTextField(labelWithString: AppVersionDisplay.string())
    private lazy var checkForUpdatesButton = NSButton(
        title: "Check for Updates…",
        target: self,
        action: #selector(checkForUpdates)
    )
    private var isUpdating = false

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 360).isActive = true
        view.heightAnchor.constraint(equalToConstant: 280).isActive = true

        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .labelColor

        let scopeLabel = NSTextField(labelWithString: "Apply Proxy To")
        scopeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        scopeLabel.textColor = .secondaryLabelColor

        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged)
        scopeControl.segmentStyle = .rounded

        let scopeStack = NSStackView(views: [scopeLabel, scopeControl])
        scopeStack.orientation = .vertical
        scopeStack.alignment = .leading
        scopeStack.spacing = 8

        let routingModeLabel = NSTextField(labelWithString: "Exclude From VPN")
        routingModeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        routingModeLabel.textColor = .secondaryLabelColor

        routingModeControl.target = self
        routingModeControl.action = #selector(routingModeChanged)
        routingModeControl.segmentStyle = .rounded

        let routingModeStack = NSStackView(views: [routingModeLabel, routingModeControl])
        routingModeStack.orientation = .vertical
        routingModeStack.alignment = .leading
        routingModeStack.spacing = 8

        let loginLabel = NSTextField(labelWithString: "Open at Login")
        loginLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        loginLabel.textColor = .labelColor

        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)

        let loginRow = NSStackView(views: [loginLabel, NSView(), loginSwitch])
        loginRow.orientation = .horizontal
        loginRow.alignment = .centerY
        loginRow.spacing = 12

        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .tertiaryLabelColor

        checkForUpdatesButton.bezelStyle = .rounded
        checkForUpdatesButton.controlSize = .small

        let versionRow = NSStackView(views: [versionLabel, NSView(), checkForUpdatesButton])
        versionRow.orientation = .horizontal
        versionRow.alignment = .centerY
        versionRow.spacing = 12

        let stack = NSStackView(views: [title, scopeStack, routingModeStack, loginRow, versionRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            scopeControl.widthAnchor.constraint(equalToConstant: 230),
            routingModeControl.widthAnchor.constraint(equalToConstant: 230),
            loginRow.widthAnchor.constraint(equalToConstant: 312),
            versionRow.widthAnchor.constraint(equalToConstant: 312)
        ])
    }

    func update(scope: ProxyNetworkScope, routingMode: DomainRoutingMode, openAtLogin: Bool) {
        isUpdating = true
        scopeControl.selectedSegment = ProxyNetworkScope.allCases.firstIndex(of: scope) ?? 0
        routingModeControl.selectedSegment = DomainRoutingMode.allCases.firstIndex(of: routingMode) ?? 0
        loginSwitch.state = openAtLogin ? .on : .off
        isUpdating = false
    }

    @objc private func scopeChanged() {
        guard !isUpdating,
              scopeControl.selectedSegment >= 0,
              scopeControl.selectedSegment < ProxyNetworkScope.allCases.count else {
            return
        }
        onScopeChange?(ProxyNetworkScope.allCases[scopeControl.selectedSegment])
    }

    @objc private func routingModeChanged() {
        guard !isUpdating,
              routingModeControl.selectedSegment >= 0,
              routingModeControl.selectedSegment < DomainRoutingMode.allCases.count else {
            return
        }
        onRoutingModeChange?(DomainRoutingMode.allCases[routingModeControl.selectedSegment])
    }

    @objc private func toggleLogin() {
        guard !isUpdating else {
            return
        }
        onToggleLogin?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }
}
