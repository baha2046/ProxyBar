import Foundation

public enum AppVersionDisplay {
    public static func string(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        guard let version = info["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            return "Version unknown"
        }

        guard let build = info["CFBundleVersion"] as? String,
              !build.isEmpty else {
            return "Version \(version)"
        }

        return "Version \(version) (Build \(build))"
    }
}
