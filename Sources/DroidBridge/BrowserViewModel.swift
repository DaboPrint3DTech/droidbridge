import SwiftUI
import AppKit

/// Una riga dell'albero delle cartelle mostrato nella barra laterale.
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

    // Albero delle cartelle (barra laterale)
    let treeRoot = "/sdcard"
    @Published var expandedPaths = Set<String>()
    @Published var treeChildren: [String: [RemoteItem]] = [:]
    @Published var loadingTreePaths = Set<String>()

    // Vista, filtri e ordinamento
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

    /// Elementi visibili dopo filtro, ricerca e ordinamento.
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

    /// Solo gli elementi selezionati che sono anche visibili: le azioni (elimina, scarica…)
    /// non toccano mai file nascosti dal filtro.
    var selectedItems: [RemoteItem] {
        displayedItems.filter { selection.contains($0.id) }
    }

    private func pruneSelection() {
        let visible = Set(displayedItems.map(\.id))
        let pruned = selection.intersection(visible)
        if pruned != selection { selection = pruned }
    }

    // MARK: - Ordinamento

    func isSorted(by keyPath: PartialKeyPath<RemoteItem>) -> Bool {
        guard let first = sortOrder.first else { return false }
        return (first.keyPath as PartialKeyPath<RemoteItem>) == keyPath
    }

    var sortAscending: Bool {
        sortOrder.first?.order != .reverse
    }

    /// Ordina per la colonna indicata; se è già quella attiva inverte il verso.
    func sort<V: Comparable>(by keyPath: KeyPath<RemoteItem, V>) {
        if isSorted(by: keyPath) {
            sortOrder = [KeyPathComparator(keyPath, order: sortAscending ? .reverse : .forward)]
        } else {
            sortOrder = [KeyPathComparator(keyPath, order: .forward)]
        }
    }

    // MARK: - Galleria

    /// Elemento mostrato in grande: il file selezionato, altrimenti la prima immagine.
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

    // MARK: - Avvio e polling dei dispositivi

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
        // Ignora i dispositivi non pronti (es. "unauthorized")
        if let serial, !devices.contains(where: { $0.serial == serial && $0.isReady }) { return }
        selectedSerial = serial
        items = []
        selection = []
        resetTree()
        if serial != nil {
            // load() riempie anche la radice dell'albero e la espande.
            load(treeRoot)
        }
    }

    // MARK: - Albero delle cartelle

    /// Righe visibili dell'albero, già "appiattite" con il livello di rientro.
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
                // Finché non sappiamo cosa c'è dentro, la freccia resta visibile.
                canExpand: known == nil || !(known?.isEmpty ?? true)
            ))
            if expanded, let children = known {
                for child in children {
                    add(path: child.path, name: child.name, depth: depth + 1)
                }
            }
        }

        add(path: treeRoot, name: "Memoria interna", depth: 0)
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

    /// Legge le sottocartelle di `path` (una sola volta, poi restano in memoria).
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
                // Cartella non leggibile (permessi): si richiude e si potrà riprovare.
                expandedPaths.remove(path)
            }
        }
    }

    /// Espande l'albero fino alla cartella indicata, così si vede dove ci si trova.
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

    /// Rilegge la cartella e tiene allineato anche l'albero.
    private func reloadItems(serial: String, path target: String) async throws {
        let result = try await ADB.list(serial: serial, path: target)
        treeChildren[target] = result.filter { $0.isDirectory }
        if target == path { items = result }
    }

    // MARK: - Navigazione

    func load(_ newPath: String? = nil) {
        guard let serial = selectedSerial else { return }
        let target = newPath ?? path
        Task {
            await perform("Caricamento…") {
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
            // Le immagini si aprono nella galleria; per salvarle si usa "Scarica".
            if viewMode != .gallery {
                selection = [item.id]
                viewMode = .gallery
            }
        } else {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            download([item], to: downloads, revealInFinder: true)
        }
    }

    // MARK: - Trasferimenti

    func downloadSelectionWithPanel() {
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Scarica qui"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        download(chosen, to: dir, revealInFinder: true)
    }

    func download(_ chosen: [RemoteItem], to directory: URL, revealInFinder: Bool) {
        guard let serial = selectedSerial else { return }
        Task {
            await perform("Download in corso…") {
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
        panel.prompt = "Invia al telefono"
        guard panel.runModal() == .OK else { return }
        upload(panel.urls)
    }

    func upload(_ urls: [URL]) {
        guard let serial = selectedSerial, !urls.isEmpty else { return }
        let destination = path
        Task {
            await perform("Upload in corso…") {
                for url in urls {
                    try await ADB.push(serial: serial, local: url, toRemoteDirectory: destination)
                }
                try await self.reloadItems(serial: serial, path: destination)
            }
        }
    }

    // MARK: - Operazioni sui file

    func deleteSelection() {
        let chosen = selectedItems
        guard let serial = selectedSerial, !chosen.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = chosen.count == 1
            ? "Eliminare “\(chosen[0].name)”?"
            : "Eliminare \(chosen.count) elementi?"
        alert.informativeText = "L'operazione è definitiva: i file non vanno nel cestino del telefono."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Elimina")
        alert.addButton(withTitle: "Annulla")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let current = path
        Task {
            await perform("Eliminazione…") {
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
        guard let name = promptForText(title: "Nuova cartella", message: "Nome della cartella:", initial: "") else { return }
        let current = path
        let full = (current.hasSuffix("/") ? current : current + "/") + name
        Task {
            await perform("Creazione cartella…") {
                try await ADB.makeDirectory(serial: serial, remote: full)
                try await self.reloadItems(serial: serial, path: current)
            }
        }
    }

    func renameSelection() {
        let chosen = selectedItems
        guard let serial = selectedSerial, chosen.count == 1, let item = chosen.first else { return }
        guard let newName = promptForText(title: "Rinomina", message: "Nuovo nome:", initial: item.name),
              newName != item.name else { return }
        let current = path
        let parent = (item.path as NSString).deletingLastPathComponent
        let target = (parent.hasSuffix("/") ? parent : parent + "/") + newName
        Task {
            await perform("Rinomina…") {
                try await ADB.rename(serial: serial, from: item.path, to: target)
                try await self.reloadItems(serial: serial, path: current)
                self.selection = []
            }
        }
    }

    // MARK: - Utilità

    private func promptForText(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Annulla")
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
