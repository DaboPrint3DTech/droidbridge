import Foundation

struct ADBError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct AndroidDevice: Identifiable, Hashable {
    let serial: String
    let model: String
    let state: String

    var id: String { serial }
    var isReady: Bool { state == "device" }
    var displayName: String {
        model.isEmpty ? serial : model.replacingOccurrences(of: "_", with: " ")
    }
}

struct RemoteItem: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modified: String

    var id: String { path }
}

/// Wrapper around the `adb` executable (Android Debug Bridge).
enum ADB {

    // MARK: - Locating adb

    static var executablePath: String? {
        var candidates: [String] = []
        if let bundled = Bundle.main.path(forResource: "adb", ofType: nil) {
            candidates.append(bundled)
        }
        candidates += [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Running

    @discardableResult
    static func run(_ arguments: [String]) async throws -> String {
        guard let path = executablePath else {
            throw ADBError(message: "adb not found. Install it with: brew install android-platform-tools")
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let out = String(decoding: outData, as: UTF8.self)
                let err = String(decoding: errData, as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    let text = (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: ADBError(message: text.isEmpty ? "adb returned an error" : text))
                }
            }
        }
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Devices

    static func devices() async throws -> [AndroidDevice] {
        let output = try await run(["devices", "-l"])
        var result: [AndroidDevice] = []
        for line in output.split(whereSeparator: \.isNewline).dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            if parts[0].hasPrefix("*") { continue } // "* daemon started"
            var model = ""
            for p in parts where p.hasPrefix("model:") {
                model = String(p.dropFirst("model:".count))
            }
            result.append(AndroidDevice(serial: parts[0], model: model, state: parts[1]))
        }
        return result
    }

    // MARK: - File system

    static func list(serial: String, path: String) async throws -> [RemoteItem] {
        let dir = path.hasSuffix("/") ? path : path + "/"
        let output = try await run(["-s", serial, "shell", "ls -laL " + shellQuote(dir)])
        return parseListing(output, in: dir)
    }

    static func parseListing(_ output: String, in dir: String) -> [RemoteItem] {
        var items: [RemoteItem] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard let first = line.first, "dlcbps-".contains(first) else { continue } // skip "total N"
            // permissions, links, user, group, size, date, time, name
            let parts = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
            guard parts.count == 8 else { continue }
            var name = String(parts[7])
            if let arrow = name.range(of: " -> ") {
                name = String(name[..<arrow.lowerBound])
            }
            if name == "." || name == ".." || name.isEmpty { continue }
            items.append(RemoteItem(
                name: name,
                path: dir + name,
                isDirectory: first == "d",
                size: Int64(parts[4]) ?? 0,
                modified: "\(parts[5]) \(parts[6])"
            ))
        }
        return items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func pull(serial: String, remote: String, to localDirectory: URL) async throws {
        try await run(["-s", serial, "pull", remote, localDirectory.path])
    }

    static func push(serial: String, local: URL, toRemoteDirectory remoteDir: String) async throws {
        let dest = remoteDir.hasSuffix("/") ? remoteDir : remoteDir + "/"
        try await run(["-s", serial, "push", local.path, dest])
    }

    static func delete(serial: String, remote: String) async throws {
        try await run(["-s", serial, "shell", "rm -rf " + shellQuote(remote)])
    }

    static func makeDirectory(serial: String, remote: String) async throws {
        try await run(["-s", serial, "shell", "mkdir -p " + shellQuote(remote)])
    }

    static func rename(serial: String, from: String, to: String) async throws {
        try await run(["-s", serial, "shell", "mv \(shellQuote(from)) \(shellQuote(to))"])
    }
}
