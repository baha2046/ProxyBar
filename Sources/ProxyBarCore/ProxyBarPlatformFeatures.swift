import Foundation

public enum ProxyBarPlatformFeatures {
    public static func usesLiquidGlass(on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        version.majorVersion >= 26
    }
}
