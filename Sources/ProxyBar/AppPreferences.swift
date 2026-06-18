import Foundation
import ProxyBarCore

enum AppPreferences {
    private static let proxyNetworkScopeKey = "proxyNetworkScope"

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
}
