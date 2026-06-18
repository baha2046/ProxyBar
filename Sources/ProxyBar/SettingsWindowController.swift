import AppKit
import ProxyBarCore

@MainActor
final class SettingsWindowController: NSWindowController {
    var onScopeChange: ((ProxyNetworkScope) -> Void)?
    var onToggleLogin: (() -> Void)?

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
        settingsViewController.onToggleLogin = { [weak self] in
            self?.onToggleLogin?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(scope: ProxyNetworkScope, openAtLogin: Bool) {
        settingsViewController.update(scope: scope, openAtLogin: openAtLogin)
    }
}

@MainActor
private final class SettingsViewController: NSViewController {
    var onScopeChange: ((ProxyNetworkScope) -> Void)?
    var onToggleLogin: (() -> Void)?

    private let scopeControl = NSSegmentedControl(labels: ProxyNetworkScope.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let loginSwitch = NSSwitch()
    private var isUpdating = false

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 360).isActive = true
        view.heightAnchor.constraint(equalToConstant: 190).isActive = true

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

        let loginLabel = NSTextField(labelWithString: "Open at Login")
        loginLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        loginLabel.textColor = .labelColor

        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)

        let loginRow = NSStackView(views: [loginLabel, NSView(), loginSwitch])
        loginRow.orientation = .horizontal
        loginRow.alignment = .centerY
        loginRow.spacing = 12

        let stack = NSStackView(views: [title, scopeStack, loginRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            scopeControl.widthAnchor.constraint(equalToConstant: 230),
            loginRow.widthAnchor.constraint(equalToConstant: 312)
        ])
    }

    func update(scope: ProxyNetworkScope, openAtLogin: Bool) {
        isUpdating = true
        scopeControl.selectedSegment = ProxyNetworkScope.allCases.firstIndex(of: scope) ?? 0
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

    @objc private func toggleLogin() {
        guard !isUpdating else {
            return
        }
        onToggleLogin?()
    }
}
