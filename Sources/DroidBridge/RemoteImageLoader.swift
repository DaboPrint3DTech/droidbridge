import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Scarica le immagini dal telefono, le ridimensiona e le tiene in cache
/// (memoria + disco in ~/Library/Caches/DroidBridge).
actor RemoteImageLoader {
    static let shared = RemoteImageLoader()

    private let memory = NSCache<NSString, NSImage>()
    private let maxConcurrent = 3
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var urgentWaiters: [CheckedContinuation<Void, Never>] = []

    private let cacheRoot: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DroidBridge", isDirectory: true)
    }()

    init() {
        memory.countLimit = 300
    }

    // MARK: - API

    func image(serial: String, item: RemoteItem, maxPixel: Int, urgent: Bool = false) async -> NSImage? {
        let usesPNG = ["png", "gif", "webp"].contains(item.ext)
        let key = stableHash("\(item.path)|\(item.size)|\(item.modified)|\(maxPixel)")
        let safeSerial = serial.replacingOccurrences(of: ":", with: "_")
        let file = cacheRoot
            .appendingPathComponent(safeSerial, isDirectory: true)
            .appendingPathComponent("\(key).\(usesPNG ? "png" : "jpg")")

        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let cached = NSImage(contentsOf: file) {
            memory.setObject(cached, forKey: key as NSString)
            return cached
        }

        await acquire(urgent: urgent)
        defer { release() }
        if Task.isCancelled { return nil }

        // Nel frattempo un'altra richiesta potrebbe aver già creato il file.
        if let cached = NSImage(contentsOf: file) {
            memory.setObject(cached, forKey: key as NSString)
            return cached
        }

        let ok = await Self.generate(serial: serial, item: item, maxPixel: maxPixel,
                                     destination: file, png: usesPNG)
        guard ok, let img = NSImage(contentsOf: file) else { return nil }
        memory.setObject(img, forKey: key as NSString)
        return img
    }

    func clearCache() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheRoot)
    }

    // MARK: - Limite di richieste contemporanee

    private func acquire(urgent: Bool) async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            if urgent {
                urgentWaiters.append(continuation)
            } else {
                waiters.append(continuation)
            }
        }
    }

    private func release() {
        if !urgentWaiters.isEmpty {
            urgentWaiters.removeFirst().resume()
        } else if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            running -= 1
        }
    }

    // MARK: - Generazione (fuori dall'actor)

    private static func generate(serial: String, item: RemoteItem, maxPixel: Int,
                                 destination: URL, png: Bool) async -> Bool {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroidBridge-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            try await ADB.pull(serial: serial, remote: item.path, to: tmp)
            let local = tmp.appendingPathComponent(item.name)

            guard let source = CGImageSourceCreateWithURL(local as CFURL, nil) else { return false }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return false
            }

            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let type = (png ? UTType.png : UTType.jpeg).identifier as CFString
            guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, type, 1, nil) else {
                return false
            }
            let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
            CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
            return CGImageDestinationFinalize(dest)
        } catch {
            return false
        }
    }

    /// Hash stabile tra un avvio e l'altro (Hasher di Swift non lo è).
    private func stableHash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }
}
