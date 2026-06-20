import AppKit
import ProxyBarCore

@MainActor
final class AddDomainWindowController: NSWindowController {
    var onAdd: ((String, Bool) -> Void)?

    private let addDomainViewController = AddDomainViewController()

    init() {
        let window = NSWindow(contentViewController: addDomainViewController)
        window.title = "Add Domain"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        addDomainViewController.onCancel = { [weak self] in
            self?.close()
        }

        addDomainViewController.onAdd = { [weak self] domain, includeWildcard in
            self?.onAdd?(domain, includeWildcard)
            self?.close()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(parentWindow: NSWindow?) {
        addDomainViewController.reset()
        if let parentWindow {
            parentWindow.beginSheet(window!)
        } else {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
private final class AddDomainViewController: NSViewController {
    var onAdd: ((String, Bool) -> Void)?
    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Add Domain")
    private let descriptionLabel = NSTextField(labelWithString: "Enter a domain name or URL to route through the proxy.")
    private let textField = NSTextField()
    private let wildcardCheckbox = NSButton(checkboxWithTitle: "Include wildcard domain (e.g. *.example.com)", target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 400).isActive = true
        view.heightAnchor.constraint(equalToConstant: 220).isActive = true

        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .labelColor

        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 3

        textField.placeholderString = "example.com"
        textField.font = .systemFont(ofSize: 13)
        textField.isEditable = true
        textField.isSelectable = true
        textField.wantsLayer = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.heightAnchor.constraint(equalToConstant: 24).isActive = true
        textField.delegate = self

        wildcardCheckbox.state = .on // Checked by default
        wildcardCheckbox.font = .systemFont(ofSize: 12)
        wildcardCheckbox.setContentCompressionResistancePriority(.required, for: .vertical)

        errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.bezelStyle = .rounded
        cancelButton.setContentCompressionResistancePriority(.required, for: .vertical)

        addButton.target = self
        addButton.action = #selector(addClicked)
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r" // Enter key
        addButton.setContentCompressionResistancePriority(.required, for: .vertical)

        let buttonStack = NSStackView(views: [cancelButton, addButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12

        let rightButtonSpacer = NSView()
        let bottomStack = NSStackView(views: [errorLabel, rightButtonSpacer, buttonStack])
        bottomStack.orientation = .horizontal
        bottomStack.alignment = .centerY
        bottomStack.distribution = .fill

        // Ensure errorLabel takes up space on the left and buttons are aligned to the right
        errorLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonStack.setContentHuggingPriority(.required, for: .horizontal)

        let mainStack = NSStackView(views: [titleLabel, descriptionLabel, textField, wildcardCheckbox, bottomStack])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textField.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40),
            bottomStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.initialFirstResponder = textField
        view.window?.makeFirstResponder(textField)
    }

    func reset() {
        textField.stringValue = ""
        wildcardCheckbox.state = .on
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    @objc private func addClicked() {
        let input = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            showError("Please enter a domain.")
            return
        }

        do {
            _ = try DomainRules.entries(for: input)
            onAdd?(input, wildcardCheckbox.state == .on)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        view.window?.layoutIfNeeded()
    }
}

extension AddDomainViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        errorLabel.isHidden = true
        errorLabel.stringValue = ""
    }
}
