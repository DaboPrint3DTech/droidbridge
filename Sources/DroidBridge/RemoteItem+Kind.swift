import Foundation

enum FileKind {
    case folder, image, video, audio, document, other
}

extension RemoteItem {
    var ext: String { (name as NSString).pathExtension.lowercased() }

    /// Case-insensitive sort key for the name.
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
        if isDirectory { return "Folder" }
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
        case .all: return "All"
        case .folders: return "Folders"
        case .images: return "Images"
        case .videos: return "Videos"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .other: return "Other files"
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
        case .list: return "List"
        case .grid: return "Grid"
        case .gallery: return "Gallery"
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
