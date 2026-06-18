public struct ProxyPopoverLayoutMetrics: Sendable {
    public let panelWidth: Int
    public let horizontalInset: Int
    public let cardSpacing: Int
    public let cardCount: Int

    public init(panelWidth: Int, horizontalInset: Int, cardSpacing: Int, cardCount: Int) {
        self.panelWidth = panelWidth
        self.horizontalInset = horizontalInset
        self.cardSpacing = cardSpacing
        self.cardCount = cardCount
    }

    public var contentWidth: Int {
        max(0, panelWidth - horizontalInset * 2)
    }

    public var cardWidth: Int {
        guard cardCount > 0 else {
            return 0
        }

        let totalSpacing = cardSpacing * max(0, cardCount - 1)
        let availableWidth = max(0, contentWidth - totalSpacing)
        return max(0, availableWidth / cardCount - 1)
    }

    public var cardsTotalWidth: Int {
        cardWidth * cardCount + cardSpacing * max(0, cardCount - 1)
    }
}
