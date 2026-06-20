import AppKit
import ProxyBarCore

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
    var requestCountsPerMinute: [Int]
    var vpnStatus: VPNStatus
    var errorMessage: String?
}

@MainActor
final class ProxyStatusViewController: NSViewController {
    var onToggleProxy: ((Bool) -> Void)?
    var onAddDomain: (() -> Void)?
    var onApply: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRemoveDomain: ((String) -> Void)?
    var onQuit: (() -> Void)?

    private let root = ProxyPanelView()
    private let statusLight = StatusLightView()
    private let titleLabel = NSTextField(labelWithString: "ProxyBar")
    private let detailLabel = NSTextField(labelWithString: "")
    private let proxySwitch = NSSwitch()
    private let activityView = ActivityStripView()
    private let vpnCard = StatusCardView(title: "VPN", showsIndicator: true)
    private let socksCard = StatusCardView(title: "SOCKS5")
    private let pacCard = StatusCardView(title: "PAC")
    private let domainsCard = StatusCardView(title: "Domains")
    private let domainList = DomainListView()
    private let errorCard = ErrorCardView()

    private let layoutMetrics = ProxyPopoverLayoutMetrics(
        panelWidth: 440,
        horizontalInset: 18,
        cardSpacing: 10,
        cardCount: 3
    )
    private var isUpdatingSwitch = false

    override func loadView() {
        preferredContentSize = NSSize(width: layoutMetrics.panelWidth, height: 748)
        view = root
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: CGFloat(layoutMetrics.panelWidth)).isActive = true

        let header = makeHeader()
        let stateBlock = makeStateBlock()
        let cards = makeCards()
        let actions = makeActions()

        let stack = NSStackView(views: [header, stateBlock, vpnCard, activityView, cards, domainList, errorCard, actions])
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(
            top: 18,
            left: CGFloat(layoutMetrics.horizontalInset),
            bottom: 16,
            right: CGFloat(layoutMetrics.horizontalInset)
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Let the domain list absorb any leftover vertical space so the panel
        // stays a fixed height regardless of how many domains are configured.
        domainList.setContentHuggingPriority(.defaultLow, for: .vertical)
        domainList.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        root.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: CGFloat(layoutMetrics.panelWidth)),
            stack.leadingAnchor.constraint(equalTo: root.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.contentView.bottomAnchor)
        ])
    }

    func update(with model: ProxyStatusViewModel) {
        titleLabel.stringValue = model.title
        detailLabel.stringValue = model.detail
        statusLight.state = model.status
        root.status = model.status
        activityView.status = model.status
        activityView.requestCounts = model.requestCountsPerMinute

        isUpdatingSwitch = true
        proxySwitch.state = model.isOn ? .on : .off
        proxySwitch.isEnabled = model.status != .working
        isUpdatingSwitch = false

        vpnCard.update(
            value: model.vpnStatus.displayName,
            status: model.vpnStatus.isConnected ? .running : .failed
        )
        socksCard.update(value: model.socksPort.map { "127.0.0.1:\($0)" } ?? "Stopped", status: model.status)
        pacCard.update(value: model.pacPort.map { "127.0.0.1:\($0)" } ?? "Stopped", status: model.status)
        domainsCard.update(value: "\(model.domainCount) rules", status: model.status)
        domainList.update(domains: model.domains, target: self, action: #selector(removeDomain(_:)))

        errorCard.message = model.errorMessage
        errorCard.isHidden = model.errorMessage == nil
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
        labels.alignment = .leading
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

        let main = NSTextField(labelWithString: "Split Tunneling for WireGuard")
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
        stack.spacing = CGFloat(layoutMetrics.cardSpacing)

        let cardWidth = CGFloat(layoutMetrics.cardWidth)
        NSLayoutConstraint.activate([
            socksCard.widthAnchor.constraint(equalToConstant: cardWidth),
            pacCard.widthAnchor.constraint(equalToConstant: cardWidth),
            domainsCard.widthAnchor.constraint(equalToConstant: cardWidth)
        ])
        return stack
    }

    private func makeActions() -> NSView {
        let addButton = actionButton(title: "Add", action: #selector(addDomain))
        let applyButton = actionButton(title: "Apply", action: #selector(applyNow))
        let configButton = actionButton(title: "Config", action: #selector(openConfig))
        let settingsButton = actionButton(title: "Settings", action: #selector(openSettings))
        let quitButton = actionButton(title: "Quit", action: #selector(quit))

        let stack = NSStackView(views: [addButton, applyButton, configButton, settingsButton, quitButton])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        
        return stack
    }

    private func actionButton(title: String, action: Selector) -> NSButton {
        let button = ProxyActionButton(title: title, target: self, action: action)
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 72).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
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

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func removeDomain(_ sender: DomainRemoveButton) {
        onRemoveDomain?(sender.domain)
    }

    @objc private func quit() {
        onQuit?()
    }
}

@MainActor
private final class DomainListView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Configured Domains")
    private let stack = NSStackView()
    private let scrollView = DomainScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No domains configured")
    private var updateState = DomainListUpdateState()

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
        scrollView.onScrollWheel = { [weak self] in
            self?.refreshRowHover()
        }
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
        guard updateState.shouldRender(domains: domains) else {
            return
        }

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

    private func refreshRowHover() {
        let mouseLocation = window?.mouseLocationOutsideOfEventStream
        for case let row as DomainRowView in stack.arrangedSubviews {
            row.updateHover(mouseLocationInWindow: mouseLocation)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
private final class DomainScrollView: NSScrollView {
    var onScrollWheel: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        onScrollWheel?()
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
    private var hoverState = MouseHoverState() {
        didSet {
            guard oldValue != hoverState else {
                return
            }
            needsDisplay = true
            setRemoveTint(hoverState.isActive ? .labelColor : .secondaryLabelColor)
        }
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
        hoverState.mouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        hoverState.mouseExited()
    }

    func updateHover(mouseLocationInWindow: NSPoint?) {
        guard let mouseLocationInWindow else {
            hoverState.contentScrolled()
            return
        }

        let localPoint = convert(mouseLocationInWindow, from: nil)
        if bounds.contains(localPoint) {
            hoverState.mouseEntered()
        } else {
            hoverState.contentScrolled()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hoverState.isActive else { return }
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
}

@MainActor
private final class DomainRemoveButton: NSButton {
    var domain = ""
}

@MainActor
private final class ProxyPanelView: NSView {
    let contentView = NSView()

    var status: StatusIcon.State = .off {
        didSet {
            updateGlassTint()
            needsDisplay = true
        }
    }

    private let usesLiquidGlass = ProxyBarPlatformFeatures.usesLiquidGlass()
    private var glassEffectView: NSView?
    private var visualEffectView: CustomVisualEffectView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    private func configureBackground() {
        contentView.translatesAutoresizingMaskIntoConstraints = false

        if usesLiquidGlass {
            if #available(macOS 26.0, *) {
                let glassView = NSGlassEffectView()
                glassView.style = .clear
                glassView.cornerRadius = 22
                glassView.tintColor = liquidGlassTint
                glassView.contentView = contentView
                glassView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(glassView)
                glassEffectView = glassView

                NSLayoutConstraint.activate([
                    glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    glassView.topAnchor.constraint(equalTo: topAnchor),
                    glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
                    contentView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
                    contentView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
                    contentView.topAnchor.constraint(equalTo: glassView.topAnchor),
                    contentView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor)
                ])
                return
            }
        }

        let vev = CustomVisualEffectView()
        vev.material = .hudWindow
        vev.blendingMode = .behindWindow
        vev.state = .active
        vev.translatesAutoresizingMaskIntoConstraints = false
        vev.glowColor = glowColor

        addSubview(vev)
        vev.addSubview(contentView)
        visualEffectView = vev

        NSLayoutConstraint.activate([
            vev.leadingAnchor.constraint(equalTo: leadingAnchor),
            vev.trailingAnchor.constraint(equalTo: trailingAnchor),
            vev.topAnchor.constraint(equalTo: topAnchor),
            vev.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: vev.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: vev.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: vev.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: vev.bottomAnchor)
        ])
    }

    private func updateGlassTint() {
        if usesLiquidGlass {
            if #available(macOS 26.0, *), let glassEffectView = glassEffectView as? NSGlassEffectView {
                glassEffectView.tintColor = liquidGlassTint
            }
        } else {
            visualEffectView?.glowColor = glowColor
        }
    }

    private var liquidGlassTint: NSColor {
        let base = NSColor(calibratedWhite: 0.08, alpha: 0.08)
        return base.blended(withFraction: 0.16, of: color(for: status)) ?? base
    }

    private var glowColor: NSColor {
        color(for: status).withAlphaComponent(0.18)
    }
}

@MainActor
private final class ProxyMarkView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        bgPath.fill()
        
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

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
    private var blinkTimer: Timer?
    private var isVisible = true

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
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
private final class ActivityStripView: NSView {
    var status: StatusIcon.State = .off {
        didSet { needsDisplay = true }
    }

    var requestCounts: [Int] = Array(repeating: 0, count: 12) {
        didSet { needsDisplay = true }
    }

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
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        bg.fill()
        NSColor.labelColor.withAlphaComponent(0.08).setStroke()
        bg.lineWidth = 1
        bg.stroke()

        let color = color(for: status)
        let gap: CGFloat = 6
        let counts = requestCounts.isEmpty ? [0] : requestCounts
        let maximum = counts.max() ?? 0
        let barWidth = (bounds.width - CGFloat(counts.count + 1) * gap) / CGFloat(counts.count)

        for (index, count) in counts.enumerated() {
            let heightRatio = maximum == 0 ? 0 : CGFloat(count) / CGFloat(maximum)
            let height = heightRatio == 0 ? 0 : max(7, (bounds.height - 18) * heightRatio)
            let x = gap + CGFloat(index) * (barWidth + gap)
            let rect = NSRect(x: x, y: bounds.height - height - 8, width: barWidth, height: height)
            guard height > 0 else {
                continue
            }
            color.withAlphaComponent(status == .off ? 0.28 : 0.86).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }
    }
}

@MainActor
private final class StatusCardView: NSView {
    private let titleLabel: NSTextField
    private let valueLabel = NSTextField(labelWithString: "")
    private let indicatorView = StatusLightView()

    init(title: String, showsIndicator: Bool = false) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingMiddle

        indicatorView.isHidden = !showsIndicator
        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicatorView.widthAnchor.constraint(equalToConstant: 8),
            indicatorView.heightAnchor.constraint(equalToConstant: 8)
        ])

        let titleRow = NSStackView(views: [titleLabel, NSView(), indicatorView])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6

        let stack = NSStackView(views: [titleRow, valueLabel])
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
        indicatorView.state = status
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.08).setStroke()
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
    case .standby, .working:
        return .systemOrange
    case .off, .failed:
        return .systemRed
    }
}

@MainActor
private final class CustomVisualEffectView: NSVisualEffectView {
    var glowColor: NSColor = .clear {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard glowColor != .clear else { return }

        let gradient = NSGradient(starting: glowColor, ending: .clear)
        let center = NSPoint(x: bounds.midX, y: 15)
        gradient?.draw(fromCenter: center, radius: 0, toCenter: center, radius: 120, options: .drawsAfterEndingLocation)
    }
}

@MainActor
final class ProxyActionButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            needsDisplay = true
        }
    }

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.isBordered = false
        self.wantsLayer = true
        self.setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)

        let baseColor = NSColor.labelColor
        let bgAlpha: CGFloat
        if isHighlighted {
            bgAlpha = 0.15
        } else if isHovered {
            bgAlpha = 0.10
        } else {
            bgAlpha = 0.05
        }
        baseColor.withAlphaComponent(bgAlpha).setFill()
        path.fill()

        let borderAlpha: CGFloat = isHovered ? 0.15 : 0.08
        baseColor.withAlphaComponent(borderAlpha).setStroke()
        path.lineWidth = 1
        path.stroke()

        let textColor = isHighlighted ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.85)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let font = self.font ?? NSFont.systemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        let titleSize = title.size(withAttributes: attributes)
        let titleRect = NSRect(
            x: 0,
            y: (bounds.height - titleSize.height) / 2 - 1,
            width: bounds.width,
            height: titleSize.height
        )
        title.draw(in: titleRect, withAttributes: attributes)
    }
}
