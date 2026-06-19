public struct MouseHoverState: Equatable {
    public private(set) var isActive: Bool

    public init(isActive: Bool = false) {
        self.isActive = isActive
    }

    public mutating func mouseEntered() {
        isActive = true
    }

    public mutating func mouseExited() {
        isActive = false
    }

    public mutating func contentScrolled() {
        isActive = false
    }
}