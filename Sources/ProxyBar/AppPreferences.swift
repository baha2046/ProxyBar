import Foundation
import ProxyBarCore

enum AppPreferences {
    private static let proxyNetworkScopeKey = "proxyNetworkScope"
    private static let domainRoutingModeKey = "domainRoutingMode"

    static var proxyNetworkScope: ProxyNetworkScope {
        get {
            guard let value = UserDefaults.standard.string(forKey: proxyNetworkScopeKey),
                  let scope = ProxyNetworkScope(rawValue: value) else {
                return .wifi
            }
            return scope
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: proxyNetworkScopeKey)
        }
    }

    static var domainRoutingMode: DomainRoutingMode {
        get {
            guard let value = UserDefaults.standard.string(forKey: domainRoutingModeKey),
                  let mode = DomainRoutingMode(rawValue: value) else {
                return .excludeListed
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: domainRoutingModeKey)
        }
    }
}
