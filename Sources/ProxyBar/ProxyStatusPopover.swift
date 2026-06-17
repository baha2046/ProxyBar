import AppKit

@MainActor
struct ProxyStatusViewModel {
    var title: String
    var detail: String
    var status: StatusIcon.State
    var isOn: Bool
    var socksPort: UInt16?
    var pacPort: UInt16?
    var domainCount: Int
    var domains: [String]
    var errorMessage: String?
    var openAtLogin: Bool
}

@MainActor
final class ProxyStatusViewController: NSViewController {
    var onToggleProxy: ((Bool) -> Void)?
    var onAddDomain: (() -> Void)?
    var onApply: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onRemoveDomain: ((String) -> Void)?
    var onToggleLogin: (() -> Void)?
    var onQuit: (() -> Void)?

    private let root = ProxyPanelView()
    private let statusLight = StatusLightView()
    private let titleLabel = NSTextField(labelWithString: "ProxyBar")
    private let detailLabel = NSTextField(labelWithString: "")
    private let proxySwitch = NSSwitch()
    private let activityView = ActivityStripView()
    private let socksCard = StatusCardView(title: "SOCKS5")
    private let pacCard = StatusCardView(title: "PAC")
    private let domainsCard = StatusCardView(title: "Domains")
    private let domainList = DomainListView()
    private let errorCard = ErrorCardView()
    private let loginButton = NSButton(title: "Open at Login", target: nil, action: nil)

    private var isUpdatingSwitch = false

    override func loadView() {
        preferredContentSize = NSSize(width: 390, height: 748)
        view = root
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 390).isActive = true

        let header = makeHeader()
        let stateBlock = makeStateBlock()
        let cards = makeCards()
        let actions = makeActions()

        let stack = NSStackView(views: [header, stateBlock, activityView, cards, domainList, errorCard, actions])
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Let the domain list absorb any leftover vertical space so the panel
        // stays a fixed height regardless of how many domains are configured.
        domainList.setContentHuggingPriority(.defaultLow, for: .vertical)
        domainList.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func update(with model: ProxyStatusViewModel) {
        titleLabel.stringValue = model.title
        detailLabel.stringValue = model.detail
        statusLight.state = model.status
        root.status = model.status
        activityView.status = model.status

        isUpdatingSwitch = true
        proxySwitch.state = model.isOn ? .on : .off
        proxySwitch.isEnabled = model.status != .working
        isUpdatingSwitch = false

        socksCard.update(value: model.socksPort.map { "127.0.0.1:\($0)" } ?? "Stopped", status: model.status)
        pacCard.update(value: model.pacPort.map { "127.0.0.1:\($0)" } ?? "Stopped", status: model.status)
        domainsCard.update(value: "\(model.domainCount) rules", status: model.status)
        domainList.update(domains: model.domains, target: self, action: #selector(removeDomain(_:)))

        errorCard.message = model.errorMessage
        errorCard.isHidden = model.errorMessage == nil

        loginButton.state = model.openAtLogin ? .on : .off
    }

    private func makeHeader() -> NSView {
        let mark = ProxyMarkView()
        mark.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 30),
            mark.heightAnchor.constraint(equalToConstant: 30)
        ])

        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .labelColor
        detailLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        detailLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.spacing = 1

        let brand = NSStackView(views: [mark, labels])
        brand.orientation = .horizontal
        brand.spacing = 10
        brand.alignment = .centerY

        statusLight.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLight.widthAnchor.constraint(equalToConstant: 12),
            statusLight.heightAnchor.constraint(equalToConstant: 12)
        ])

        proxySwitch.target = self
        proxySwitch.action = #selector(toggleProxy)

        let right = NSStackView(views: [statusLight, proxySwitch])
        right.orientation = .horizontal
        right.spacing = 11
        right.alignment = .centerY

        let header = NSStackView(views: [brand, NSView(), right])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        return header
    }

    private func makeStateBlock() -> NSView {
        let block = RoundedBlockView()
        block.translatesAutoresizingMaskIntoConstraints = false

        let main = NSTextField(labelWithString: "Local proxy control")
        main.font = .systemFont(ofSize: 13, weight: .semibold)
        main.textColor = .secondaryLabelColor
        main.lineBreakMode = .byWordWrapping

        let hint = NSTextField(labelWithString: "Toggle routing, then confirm the SOCKS5 and PAC listeners below.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [main, hint])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        block.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: block.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -12)
        ])
        return block
    }

    private func makeCards() -> NSView {
        let stack = NSStackView(views: [socksCard, pacCard, domainsCard])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        return stack
    }

    private func makeActions() -> NSView {
        let addButton = actionButton(title: "Add", action: #selector(addDomain))
        let applyButton = actionButton(title: "Apply", action: #selector(applyNow))
        let configButton = actionButton(title: "Config", action: #selector(openConfig))
        let quitButton = actionButton(title: "Quit", action: #selector(quit))

        loginButton.target = self
        loginButton.action = #selector(toggleLogin)
        loginButton.setButtonType(.switch)
        loginButton.font = .systemFont(ofSize: 12, weight: .semibold)

        let top = NSStackView(views: [addButton, applyButton, configButton, quitButton])
        top.orientation = .horizontal
        top.distribution = .fillEqually
        top.spacing = 8

        let stack = NSStackView(views: [loginButton, top])
        stack.orientation = .vertical
        stack.spacing = 10
        return stack
    }

    private func actionButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        return button
    }

    @objc private func toggleProxy() {
        guard !isUpdatingSwitch else {
            return
        }
        onToggleProxy?(proxySwitch.state == .on)
    }

    @objc private func addDomain() {
        onAddDomain?()
    }

    @objc private func applyNow() {
        onApply?()
    }

    @objc private func openConfig() {
        onOpenConfig?()
    }

    @objc private func removeDomain(_ sender: DomainRemoveButton) {
        onRemoveDomain?(sender.domain)
    }

    @objc private func toggleLogin() {
        onToggleLogin?()
    }

    @objc private func quit() {
        onQuit?()
    }
}

@MainActor
private final class DomainListView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Configured Domains")
    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No domains configured")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor

        stack.orientation = .vertical
        stack.spacing = 5
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        ])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.documentView = documentView
        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.isHidden = true

        let container = NSStackView(views: [titleLabel, scrollView])
        container.orientation = .vertical
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)
        addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func update(domains: [String], target: AnyObject, action: Selector) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        titleLabel.stringValue = domains.isEmpty
            ? "Configured Domains"
            : "Configured Domains (\(domains.count))"

        emptyLabel.isHidden = !domains.isEmpty
        scrollView.isHidden = domains.isEmpty

        for domain in domains {
            let row = DomainRowView(domain: domain, target: target, action: action)
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }

        // Scroll back to the top after a refresh.
        scrollView.documentView?.scroll(.zero)

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.15, alpha: 0.68).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.07).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class DomainRowView: NSView {
    private let domainLabel = NSTextField(labelWithString: "")
    private let removeButton: DomainRemoveButton
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    init(domain: String, target: AnyObject, action: Selector) {
        removeButton = DomainRemoveButton()
        super.init(frame: .zero)

        domainLabel.stringValue = domain
        domainLabel.font = .systemFont(ofSize: 12, weight: .medium)
        domainLabel.textColor = .labelColor
        domainLabel.lineBreakMode = .byTruncatingMiddle
        domainLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        domainLabel.translatesAutoresizingMaskIntoConstraints = false

        removeButton.domain = domain
        removeButton.target = target
        removeButton.action = action
        removeButton.isBordered = false
        removeButton.bezelStyle = .inline
        removeButton.toolTip = "Remove \(domain)"
        removeButton.setButtonType(.momentaryChange)
        removeButton.imagePosition = .imageOnly
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.setContentHuggingPriority(.required, for: .horizontal)
        setRemoveTint(.secondaryLabelColor)

        addSubview(domainLabel)
        addSubview(removeButton)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            domainLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            domainLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.leadingAnchor.constraint(greaterThanOrEqualTo: domainLabel.trailingAnchor, constant: 8),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 18),
            removeButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    private func setRemoveTint(_ color: NSColor) {
        let title = NSAttributedString(
            string: "✕",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: color
            ]
        )
        removeButton.attributedTitle = title
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        setRemoveTint(.labelColor)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        setRemoveTint(.secondaryLabelColor)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovering else { return }
        NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
}

@MainActor
private final class DomainRemoveButton: NSButton {
    var domain = ""
}

@MainActor
private final class ProxyPanelView: NSView {
    var status: StatusIcon.State = .off {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.105, alpha: 0.98).setFill()
        bounds.fill()

        glowColor.setFill()
        let glow = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 90, y: -50, width: 180, height: 130))
        glow.fill()
    }

    private var glowColor: NSColor {
        color(for: status).withAlphaComponent(0.13)
    }
}

@MainActor
private final class ProxyMarkView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

        NSColor.labelColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 8, y: 10))
        path.line(to: NSPoint(x: 20, y: 10))
        path.move(to: NSPoint(x: 16, y: 7))
        path.line(to: NSPoint(x: 21, y: 10))
        path.line(to: NSPoint(x: 16, y: 13))
        path.move(to: NSPoint(x: 22, y: 20))
        path.line(to: NSPoint(x: 10, y: 20))
        path.move(to: NSPoint(x: 14, y: 17))
        path.line(to: NSPoint(x: 9, y: 20))
        path.line(to: NSPoint(x: 14, y: 23))
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

@MainActor
private final class StatusLightView: NSView {
    var state: StatusIcon.State = .off {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = color(for: state)
        color.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: -3, dy: -3)).fill()
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

@MainActor
private final class RoundedBlockView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.16, alpha: 0.92).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
private final class ActivityStripView: NSView {
    var status: StatusIcon.State = .off {
        didSet { needsDisplay = true }
    }

    private let heights: [CGFloat] = [0.24, 0.55, 0.34, 0.72, 0.42, 0.88, 0.64, 0.35, 0.76, 0.48, 0.28, 0.58]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 64).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.14, alpha: 0.78).setFill()
        bg.fill()

        let color = color(for: status)
        let gap: CGFloat = 6
        let barWidth = (bounds.width - CGFloat(heights.count + 1) * gap) / CGFloat(heights.count)
        for (index, heightRatio) in heights.enumerated() {
            let height = max(7, (bounds.height - 18) * heightRatio)
            let x = gap + CGFloat(index) * (barWidth + gap)
            let rect = NSRect(x: x, y: bounds.height - height - 8, width: barWidth, height: height)
            color.withAlphaComponent(status == .off ? 0.28 : 0.86).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }
    }
}

@MainActor
private final class StatusCardView: NSView {
    private let titleLabel: NSTextField
    private let valueLabel = NSTextField(labelWithString: "")

    init(title: String) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [titleLabel, valueLabel])
        stack.orientation = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 62).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func update(value: String, status: StatusIcon.State) {
        valueLabel.stringValue = value
        valueLabel.textColor = status == .failed ? .systemRed : .labelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.15, alpha: 0.86).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
private final class ErrorCardView: NSView {
    private let label = NSTextField(labelWithString: "")

    var message: String? {
        didSet {
            label.stringValue = message ?? ""
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .systemRed
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 4
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.withAlphaComponent(0.10).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()
        NSColor.systemRed.withAlphaComponent(0.30).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
private func color(for state: StatusIcon.State) -> NSColor {
    switch state {
    case .running:
        return .systemGreen
    case .off, .failed:
        return .systemRed
    case .working:
        return .systemOrange
    }
}
