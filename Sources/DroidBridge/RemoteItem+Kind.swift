import Foundation

enum FileKind {
    case folder, image, video, audio, document, other
}

extension RemoteItem {
    var ext: String { (name as NSString).pathExtension.lowercased() }

    /// Chiave di ordinamento per nome, senza distinzione tra maiuscole e minuscole.
    var sortName: String { name.lowercased() }

    var kind: FileKind {
        if isDirectory { return .folder }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tif", "tiff":
            return .image
        case "mp4", "mov", "mkv", "avi", "3gp", "webm", "m4v":
            return .video
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus":
            return .audio
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "csv", "odt":
            return .document
        default:
            return .other
        }
    }

    var typeLabel: String {
        if isDirectory { return "Cartella" }
        return ext.isEmpty ? "File" : ext.uppercased()
    }

    var symbolName: String {
        switch kind {
        case .folder: return "folder.fill"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .document: return "doc.text"
        case .other: return "doc"
        }
    }
}

enum ItemFilter: String, CaseIterable, Identifiable {
    case all, folders, images, videos, audio, documents, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Tutti"
        case .folders: return "Cartelle"
        case .images: return "Immagini"
        case .videos: return "Video"
        case .audio: return "Audio"
        case .documents: return "Documenti"
        case .other: return "Altri file"
        }
    }

    func matches(_ item: RemoteItem) -> Bool {
        switch self {
        case .all: return true
        case .folders: return item.kind == .folder
        case .images: return item.kind == .image
        case .videos: return item.kind == .video
        case .audio: return item.kind == .audio
        case .documents: return item.kind == .document
        case .other: return item.kind == .other
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case list, grid, gallery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: return "Lista"
        case .grid: return "Griglia"
        case .gallery: return "Galleria"
        }
    }

    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        case .gallery: return "photo.on.rectangle"
        }
    }
}
