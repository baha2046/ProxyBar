import AppKit

@MainActor
enum StatusIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.labelColor.setStroke()
        NSColor.labelColor.setFill()

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

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "ProxyBar"
        return image
    }
}
