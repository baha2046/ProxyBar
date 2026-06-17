import AppKit

@MainActor
enum StatusIcon {
    enum State {
        case running
        case off
        case working
        case failed
    }

    static func make(state: State = .off) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        let bodyColor = NSColor.labelColor
        bodyColor.setStroke()
        bodyColor.withAlphaComponent(0.88).setFill()

        let frame = NSRect(x: 2.5, y: 3, width: 13, height: 12)
        let rounded = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
        rounded.lineWidth = 1.8
        rounded.stroke()

        let split = NSBezierPath()
        split.move(to: NSPoint(x: 9, y: 3))
        split.line(to: NSPoint(x: 9, y: 15))
        split.lineWidth = 1.3
        split.stroke()

        let leftDot = NSBezierPath(ovalIn: NSRect(x: 5, y: 8, width: 2.2, height: 2.2))
        leftDot.fill()
        let rightDot = NSBezierPath(ovalIn: NSRect(x: 10.8, y: 8, width: 2.2, height: 2.2))
        rightDot.fill()

        statusColor(for: state).setFill()
        let light = NSBezierPath(ovalIn: NSRect(x: 12.2, y: 2.3, width: 4.6, height: 4.6))
        light.fill()

        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription(for: state)
        return image
    }

    private static func statusColor(for state: State) -> NSColor {
        switch state {
        case .running:
            return NSColor.systemGreen
        case .off, .failed:
            return NSColor.systemRed
        case .working:
            return NSColor.systemOrange
        }
    }

    private static func accessibilityDescription(for state: State) -> String {
        switch state {
        case .running:
            return "ProxyBar running"
        case .off:
            return "ProxyBar off"
        case .working:
            return "ProxyBar applying settings"
        case .failed:
            return "ProxyBar failed"
        }
    }
}
