import Foundation

public enum AddDomainPresentationMode: Equatable {
    case sheet
    case standalone
}

public enum AddDomainPresentationDecision {
    public static func mode(popoverIsShown: Bool, hasPopoverWindow: Bool) -> AddDomainPresentationMode {
        popoverIsShown && hasPopoverWindow ? .sheet : .standalone
    }
}
