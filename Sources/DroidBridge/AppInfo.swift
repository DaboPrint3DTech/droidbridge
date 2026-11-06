import Foundation

/// Dati mostrati nella finestra "Informazioni". Per cambiarli basta modificare questo file.
enum AppInfo {
    static let name = "DroidBridge"
    static let creator = "Davide Bossi"
    static let year = "2026"
    static let summary = "Sfoglia e trasferisci file tra il Mac e un telefono Android tramite ADB."
    static let disclaimer = "DroidBridge è un progetto indipendente: non è affiliato a MacDroid, Google o Android."

    // Usati solo quando l'app gira senza essere impacchettata (swift run).
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

    /// Versione di adb installata sul Mac, ricavata da `adb version`.
    static func adbVersion() async -> String {
        guard let output = try? await ADB.run(["version"]) else { return "non disponibile" }
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let main = (lines.first ?? "")
            .replacingOccurrences(of: "Android Debug Bridge version ", with: "")
        if let detail = lines.first(where: { $0.hasPrefix("Version ") }) {
            return "\(main) (\(detail.replacingOccurrences(of: "Version ", with: "")))"
        }
        return main.isEmpty ? "non disponibile" : main
    }
}
