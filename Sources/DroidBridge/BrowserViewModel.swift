import SwiftUI
import AppKit

/// A row of the folder tree shown in the sidebar.
struct TreeRow: Identifiable, Hashable {
    let path: String
    let name: String
    let depth: Int
    let isExpanded: Bool
    let isLoading: Bool
    let canExpand: Bool

    var id: String { path }
}

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var devices: [AndroidDevice] = []
    @Published var selectedSerial: String?
    @Published var path = "/sdcard"
    @Published var items: [RemoteItem] = []
    @Published var selection = Set<RemoteItem.ID>()
    @Published var busyMessage: String?
    @Published var errorMessage: String?
    @Published var adbMissing = false

    // Folder tree (sidebar)
    let treeRoot = "/sdcard"
    @Published var expandedPaths = Set<String>()
    @Published var treeChildren: [String: [RemoteItem]] = [:]
    @Published var loadingTreePaths = Set<String>()

    // View, filters and sorting
    @Published var viewMode: ViewMode = .list
    @Published var showPreview = true
    @Published var thumbSize: Double = 130
    @Published var searchText = "" { didSet { pruneSelection() } }
    @Published var filter: ItemFilter = .all { didSet { pruneSelection() } }
    @Published var foldersFirst = true
    @Published var sortOrder: [KeyPathComparator<RemoteItem>] = [KeyPathComparator(\RemoteItem.sortName)]

    private var timer: Timer?

    var selectedDevice: AndroidDevice? {
        devices.first { $0.serial == selectedSerial }
    }

    /// Items visible after filtering, searching and sorting.
    var displayedItems: [RemoteItem] {
        var result = items.filter { filter.matches($0) }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        result = result.sorted(using: sortOrder)
        if foldersFirst {
            result = result.filter { $0.isDirectory } + result.filter { !$0.isDirectory }
        }
        return result
    }

    /// Only the selected items that are also visible: actions (delete, download…)
    /// never touch files hidden by the filter.
    var selectedItems: [RemoteItem] {
        displayedItems.filter { selection.contains($0.id) }
    }

    private func pruneSelection() {
        let visible = Set(displayedItems.map(\.id))
        let pruned = selection.intersection(visible)
        if pruned != selection { selection = pruned }
    }

    // MARK: - Sorting

    func isSorted(by keyPath: PartialKeyPath<RemoteItem>) -> Bool {
        guard let first = sortOrder.first else { return false }
        return (first.keyPath as PartialKeyPath<RemoteItem>) == keyPath
    }

    var sortAscending: Bool {
        sortOrder.first?.order != .reverse
    }

    /// Sorts by the given column; if it is already active, reverses the order.
    func sort<V: Comparable>(by keyPath: KeyPath<RemoteItem, V>) {
        if isSorted(by: keyPath) {
            sortOrder = [KeyPathComparator(keyPath, order: sortAscending ? .reverse : .forward)]
        } else {
            sortOrder = [KeyPathComparator(keyPath, order: .forward)]
        }
    }

    // MARK: - Gallery

    /// Item shown large: the selected file, otherwise the first image.
    var galleryItem: RemoteItem? {
        let shown = displayedItems
        if let selected = shown.first(where: { selection.contains($0.id) && !$0.isDirectory }) {
            return selected
        }
        return shown.first { $0.kind == .image }
    }

    func stepGallery(_ delta: Int) {
        let images = displayedItems.filter { $0.kind == .image }
        guard !images.isEmpty else { return }
        let current = images.firstIndex { $0.id == galleryItem?.id } ?? -1
        let next = min(max(current + delta, 0), images.count - 1)
        selection = [images[next].id]
    }

    func clearPreviewCache() {
        Task { await RemoteImageLoader.shared.clearCache() }
    }

    // MARK: - Startup and device polling

    func start() {
        adbMissing = ADB.executablePath == nil
        guard !adbMissing else { return }
        Task { await refreshDevices() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.busyMessage == nil else { return }
                await self.refreshDevices()
            }
        }
    }

    func refreshDevices() async {
        guard let found = try? await ADB.devices() else { return }
        if found != devices { devices = found }

        if let current = selectedSerial, !found.contains(where: { $0.serial == current && $0.isReady }) {
            selectedSerial = nil
            items = []
            resetTree()
        }
        if selectedSerial == nil, let first = found.first(where: { $0.isReady }) {
            select(first.serial)
        }
    }

    func select(_ serial: String?) {
        guard serial != selectedSerial else { return }
        // Ignore devices that are not ready (e.g. "unauthorized")
        if let serial, !devices.contains(where: { $0.serial == serial && $0.isReady }) { return }
        selectedSerial = serial
        items = []
        selection = []
        resetTree()
        if serial != nil {
            // load() also fills the tree root and expands it.
            load(treeRoot)
        }
    }

    // MARK: - Folder tree

    /// Visible tree rows, already flattened with their indent level.
    var treeRows: [TreeRow] {
        var rows: [TreeRow] = []

        func add(path: String, name: String, depth: Int) {
            let known = treeChildren[path]
            let expanded = expandedPaths.contains(path)
            rows.append(TreeRow(
                path: path,
                name: name,
                depth: depth,
                isExpanded: expanded,
                isLoading: loadingTreePaths.contains(path),
                // Until we know what is inside, the disclosure arrow stays visible.
                canExpand: known == nil || !(known?.isEmpty ?? true)
            ))
            if expanded, let children = known {
                for child in children {
                    add(path: child.path, name: child.name, depth: depth + 1)
                }
            }
        }

        add(path: treeRoot, name: "Internal storage", depth: 0)
        return rows
    }

    private func resetTree() {
        expandedPaths = []
        treeChildren = [:]
        loadingTreePaths = []
    }

    func toggleTree(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            loadTreeChildren(path)
        }
    }

    /// Reads the subfolders of `path` (only once, then they stay in memory).
    func loadTreeChildren(_ path: String) {
        guard let serial = selectedSerial,
              treeChildren[path] == nil,
              !loadingTreePaths.contains(path) else { return }
        loadingTreePaths.insert(path)
        Task {
            let listing = try? await ADB.list(serial: serial, path: path)
            loadingTreePaths.remove(path)
            guard serial == selectedSerial else { return }
            if let listing {
                treeChildren[path] = listing.filter { $0.isDirectory }
            } else {
                // Unreadable folder (permissions): collapse it so it can be retried.
                expandedPaths.remove(path)
            }
        }
    }

    /// Expands the tree down to the given folder, so you can see where you are.
    func revealInTree(_ target: String) {
        guard target == treeRoot || target.hasPrefix(treeRoot + "/") else { return }
        var current = treeRoot
        var ancestors = [treeRoot]
        let rest = target.dropFirst(treeRoot.count).split(separator: "/")
        for component in rest.dropLast() {
            current += "/" + component
            ancestors.append(current)
        }
        for path in ancestors {
            expandedPaths.insert(path)
            loadTreeChildren(path)
        }
    }

    /// Reloads the folder and keeps the tree in sync.
    private func reloadItems(serial: String, path target: String) async throws {
        let result = try await ADB.list(serial: serial, path: target)
        treeChildren[target] = result.filter { $0.isDirectory }
        if target == path { items = result }
    }

    // MARK: - Navigation

    func load(_ newPath: String? = nil) {
        guard let serial = selectedSerial else { return }
        let target = newPath ?? path
        Task {
            await perform("Loading…") {
                let result = try await ADB.list(serial: serial, path: target)
                if target != self.path { self.searchText = "" }
                self.path = target
                self.items = result
                self.treeChildren[target] = result.filter { $0.isDirectory }
                self.selection = []
                self.revealInTree(target)
            }
        }
    }

    func goUp() {
        guard path != "/" else { return }
        let parent = (path as NSString).deletingLastPathComponent
        load(parent.isEmpty ? "/" : parent)
    }

    func open(ids: Set<RemoteItem.ID>) {
        let chosen = items.filter { ids.contains($0.id) }
        guard chosen.count == 1, let item = chosen.first else { return }
        if item.isDirectory {
            load(item.path)
        } else if item.kind == .image {
            // Images open in the gallery; use "Download" to save them.
            if viewMode != .gallery {
                selection = [item.id]
                viewMode = .gallery
            }
        } else {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            download([item], to: downloads, revealInFinder: true)
        }
    }

    // MARK: - Transfers

    func downloadSelectionWithPanel() {
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Download Here"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        download(chosen, to: dir, revealInFinder: true)
    }

    func download(_ chosen: [RemoteItem], to directory: URL, revealInFinder: Bool) {
        guard let serial = selectedSerial else { return }
        Task {
            await perform("Downloading…") {
                for item in chosen {
                    try await ADB.pull(serial: serial, remote: item.path, to: directory)
                }
                if revealInFinder {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        chosen.map { directory.appendingPathComponent($0.name) }
                    )
                }
            }
        }
    }

    func uploadWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Send to Phone"
        guard panel.runModal() == .OK else { return }
        upload(panel.urls)
    }

    func upload(_ urls: [URL]) {
        guard let serial = selectedSerial, !urls.isEmpty else { return }
        let destination = path
        Task {
            await perform("Uploading…") {
                for url in urls {
                    try await ADB.push(serial: serial, local: url, toRemoteDirectory: destination)
                }
                try await self.reloadItems(serial: serial, path: destination)
            }
        }
    }

    // MARK: - File operations

    func deleteSelection() {
        let chosen = selectedItems
        guard let serial = selectedSerial, !chosen.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = chosen.count == 1
            ? "Delete “\(chosen[0].name)”?"
            : "Delete \(chosen.count) items?"
        alert.informativeText = "This cannot be undone: the files are not moved to the phone's trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let current = path
        Task {
            await perform("Deleting…") {
                for item in chosen {
                    try await ADB.delete(serial: serial, remote: item.path)
                }
                try await self.reloadItems(serial: serial, path: current)
                self.selection = []
            }
        }
    }

    func newFolder() {
        guard let serial = selectedSerial else { return }
        guard let name = promptForText(title: "New Folder", message: "Folder name:", initial: "") else { return }
        let current = path
        let full = (current.hasSuffix("/") ? current : current + "/") + name
        Task {
            await perform("Creating folder…") {
                try await ADB.makeDirectory(serial: serial, remote: full)
                try await self.reloadItems(serial: serial, path: current)
            }
        }
    }

    func renameSelection() {
        let chosen = selectedItems
        guard let serial = selectedSerial, chosen.count == 1, let item = chosen.first else { return }
        guard let newName = promptForText(title: "Rename", message: "New name:", initial: item.name),
              newName != item.name else { return }
        let current = path
        let parent = (item.path as NSString).deletingLastPathComponent
        let target = (parent.hasSuffix("/") ? parent : parent + "/") + newName
        Task {
            await perform("Renaming…") {
                try await ADB.rename(serial: serial, from: item.path, to: target)
                try await self.reloadItems(serial: serial, path: current)
                self.selection = []
            }
        }
    }

    // MARK: - Utilities

    private func promptForText(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.contains("/") ? nil : value
    }

    private func perform(_ message: String, _ work: @MainActor () async throws -> Void) async {
        busyMessage = message
        defer { busyMessage = nil }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
