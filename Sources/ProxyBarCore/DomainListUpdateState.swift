import Foundation

public struct DomainListUpdateState {
    private var renderedDomains: [String] = []

    public init() {}

    public mutating func shouldRender(domains: [String]) -> Bool {
        guard domains != renderedDomains else {
            return false
        }

        renderedDomains = domains
        return true
    }
}
