import Foundation

/// Data shown in the "About" window. Edit this file to change it.
enum AppInfo {
    static let name = "DroidBridge"
    static let creator = "Davide Bossi"
    static let year = "2026"
    static let summary = "Browse and transfer files between your Mac and an Android phone over ADB."
    static let disclaimer = "DroidBridge is an independent project, not affiliated with MacDroid, Google or Android."

    // Used only when the app runs unbundled (swift run).
    private static let fallbackVersion = "1.2"
    private static let fallbackBuild = "3"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? fallbackBuild
    }

    static var versionString: String { "\(version) (build \(build))" }

    static var copyright: String { "© \(year) \(creator)" }

    /// Version of adb installed on the Mac, read from `adb version`.
    static func adbVersion() async -> String {
        guard let output = try? await ADB.run(["version"]) else { return "not available" }
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let main = (lines.first ?? "")
            .replacingOccurrences(of: "Android Debug Bridge version ", with: "")
        if let detail = lines.first(where: { $0.hasPrefix("Version ") }) {
            return "\(main) (\(detail.replacingOccurrences(of: "Version ", with: "")))"
        }
        return main.isEmpty ? "not available" : main
    }
}
