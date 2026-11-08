import SwiftUI
import UniformTypeIdentifiers

/// Thumbnails are generated at a single resolution for every view, so each image
/// is downloaded from the phone only once and then reused from the cache.
private let thumbPixels = 480
private let galleryPixels = 2400

struct ContentView: View {
    @StateObject private var vm = BrowserViewModel()
    @State private var anchorID: RemoteItem.ID?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if vm.adbMissing {
                AdbMissingView()
            } else {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 210, ideal: 250)
                } detail: {
                    detail
                }
            }
        }
        .onAppear { vm.start() }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding<String?>(
            get: { vm.selectedSerial },
            // Tree rows have no tag: clicking them must not deselect the phone.
            set: { if let serial = $0 { vm.select(serial) } }
        )) {
            Section("Devices") {
                ForEach(vm.devices) { device in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.displayName)
                            if !device.isReady {
                                Text(stateDescription(device.state))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } icon: {
                        Image(systemName: "smartphone")
                    }
                    .tag(device.serial as String?)

                    // Folder tree, under the selected phone
                    if device.serial == vm.selectedSerial {
                        ForEach(vm.treeRows) { row in
                            treeRow(row)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { aboutButton }
        .overlay {
            if vm.devices.isEmpty {
                Text("No devices")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func treeRow(_ row: TreeRow) -> some View {
        let isCurrent = row.path == vm.path
        return HStack(spacing: 4) {
            Group {
                if row.isLoading {
                    ProgressView().controlSize(.mini)
                } else if row.canExpand {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.toggleTree(row.path) }
                } else {
                    Color.clear
                }
            }
            .frame(width: 14, height: 14)

            Image(systemName: row.depth == 0 ? "internaldrive" : "folder")
                .foregroundStyle(Color.accentColor)
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 12 + 14)
        .padding(.vertical, 2)
        .background(
            isCurrent ? Color.accentColor.opacity(0.22) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(Rectangle())
        .onTapGesture { vm.load(row.path) }
        .help(row.path)
    }

    private var aboutButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                openWindow(id: "about")
            } label: {
                Label("About \(AppInfo.name) \(AppInfo.version)", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(10)
        }
    }

    private func stateDescription(_ state: String) -> String {
        switch state {
        case "unauthorized": return "Allow this Mac on the phone"
        case "offline": return "Offline"
        default: return state
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let serial = vm.selectedSerial, vm.selectedDevice != nil {
            fileBrowser(serial: serial)
        } else {
            NoDeviceView()
        }
    }

    private func fileBrowser(serial: String) -> some View {
        let shown = vm.displayedItems
        return VStack(spacing: 0) {
            pathBar
            Divider()
            content(shown, serial: serial)
                .overlay { emptyState(shown) }
                .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers)
                }
            Divider()
            statusBar(shown)
        }
        .searchable(text: $vm.searchText, placement: .toolbar, prompt: "Filter by name")
        .toolbar { toolbarContent }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(vm.path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            if let message = vm.busyMessage {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func content(_ shown: [RemoteItem], serial: String) -> some View {
        switch vm.viewMode {
        case .list: listView(shown, serial: serial)
        case .grid: gridView(shown, serial: serial)
        case .gallery: galleryView(shown, serial: serial)
        }
    }

    @ViewBuilder
    private func emptyState(_ shown: [RemoteItem]) -> some View {
        if shown.isEmpty && vm.viewMode != .gallery && vm.busyMessage == nil {
            if vm.items.isEmpty {
                Text("Empty folder")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    Text("No items match the filters")
                        .foregroundStyle(.secondary)
                    Button("Clear Filters") {
                        vm.searchText = ""
                        vm.filter = .all
                    }
                }
            }
        }
    }

    // MARK: - List view

    private func listView(_ shown: [RemoteItem], serial: String) -> some View {
        Table(shown, selection: $vm.selection, sortOrder: $vm.sortOrder) {
            TableColumn("Name", value: \RemoteItem.sortName) { item in
                HStack(spacing: 6) {
                    itemIcon(item, serial: serial, side: 22)
                    Text(item.name).lineLimit(1)
                }
            }
            TableColumn("Size", value: \RemoteItem.size) { item in
                Text(item.isDirectory ? "—" : formattedSize(item.size))
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn("Kind", value: \RemoteItem.typeLabel) { item in
                Text(item.typeLabel)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80, max: 120)
            TableColumn("Modified", value: \RemoteItem.modified) { item in
                Text(item.modified)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140, max: 170)
        }
        .contextMenu(forSelectionType: RemoteItem.ID.self) { ids in
            tableMenu(ids)
        } primaryAction: { ids in
            vm.open(ids: ids)
        }
    }

    @ViewBuilder
    private func tableMenu(_ ids: Set<RemoteItem.ID>) -> some View {
        if ids.count == 1 {
            Button("Open") { vm.open(ids: ids) }
            Button("Rename…") { vm.renameSelection() }
        }
        if !ids.isEmpty {
            Button("Download to Mac…") { vm.downloadSelectionWithPanel() }
            Divider()
            Button("Delete…", role: .destructive) { vm.deleteSelection() }
        }
    }

    @ViewBuilder
    private func itemIcon(_ item: RemoteItem, serial: String, side: CGFloat) -> some View {
        if item.kind == .image && vm.showPreview {
            RemoteImageView(serial: serial, item: item, maxPixel: thumbPixels, contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: item.symbolName)
                .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: side, height: side)
        }
    }

    // MARK: - Grid view

    private func gridView(_ shown: [RemoteItem], serial: String) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: vm.thumbSize + 12), spacing: 10)],
                spacing: 10
            ) {
                ForEach(shown) { item in
                    gridCell(item, shown: shown, serial: serial)
                }
            }
            .padding(12)
        }
        .background(
            Color(nsColor: .textBackgroundColor)
                .onTapGesture { vm.selection = [] }
        )
    }

    private func gridCell(_ item: RemoteItem, shown: [RemoteItem], serial: String) -> some View {
        let selected = vm.selection.contains(item.id)
        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                if item.kind == .image && vm.showPreview {
                    RemoteImageView(serial: serial, item: item, maxPixel: thumbPixels, contentMode: .fit)
                        .padding(4)
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: vm.thumbSize * 0.4))
                        .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
                }
            }
            .frame(width: vm.thumbSize, height: vm.thumbSize)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: vm.thumbSize)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    selected ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { vm.open(ids: [item.id]) }
        .onTapGesture { handleTap(item, in: shown) }
        .contextMenu {
            Button("Open") { vm.open(ids: [item.id]) }
            Button("Rename…") {
                vm.selection = [item.id]
                vm.renameSelection()
            }
            Button("Download to Mac…") {
                ensureSelected(item)
                vm.downloadSelectionWithPanel()
            }
            Divider()
            Button("Delete…", role: .destructive) {
                ensureSelected(item)
                vm.deleteSelection()
            }
        }
        .help(item.name)
    }

    private func ensureSelected(_ item: RemoteItem) {
        if !vm.selection.contains(item.id) {
            vm.selection = [item.id]
        }
    }

    /// Single click: ⌘ adds to or removes from the selection, ⇧ selects a range.
    private func handleTap(_ item: RemoteItem, in shown: [RemoteItem]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if vm.selection.contains(item.id) {
                vm.selection.remove(item.id)
            } else {
                vm.selection.insert(item.id)
            }
            anchorID = item.id
        } else if flags.contains(.shift),
                  let anchor = anchorID,
                  let a = shown.firstIndex(where: { $0.id == anchor }),
                  let b = shown.firstIndex(where: { $0.id == item.id }) {
            vm.selection = Set(shown[min(a, b)...max(a, b)].map(\.id))
        } else {
            vm.selection = [item.id]
            anchorID = item.id
        }
    }

    // MARK: - Gallery

    private func galleryView(_ shown: [RemoteItem], serial: String) -> some View {
        let images = shown.filter { $0.kind == .image }
        let current = vm.galleryItem
        let position = images.firstIndex { $0.id == current?.id }
        let canGoBack = (position ?? 0) > 0
        let canGoForward = !images.isEmpty && (position ?? -1) < images.count - 1

        return VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let item = current {
                    galleryStage(item, serial: serial)
                } else {
                    Text("No images in this folder")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    galleryArrow("chevron.left.circle.fill", delta: -1, key: .leftArrow, enabled: canGoBack)
                    Spacer()
                    galleryArrow("chevron.right.circle.fill", delta: 1, key: .rightArrow, enabled: canGoForward)
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            galleryInfo(current, position: position, total: images.count)
            Divider()
            filmstrip(shown, serial: serial, currentID: current?.id)
        }
    }

    @ViewBuilder
    private func galleryStage(_ item: RemoteItem, serial: String) -> some View {
        if item.kind == .image {
            ZStack {
                // The small thumbnail shows up at once; the large image replaces it as soon as it is ready.
                RemoteImageView(serial: serial, item: item, maxPixel: thumbPixels, contentMode: .fit)
                RemoteImageView(serial: serial, item: item, maxPixel: galleryPixels,
                                urgent: true, contentMode: .fit, showsPlaceholder: false)
            }
            .id(item.id)
            .padding(16)
        } else {
            VStack(spacing: 8) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text(item.name).font(.headline)
                Text("No preview available for this file type")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func galleryArrow(_ symbol: String, delta: Int, key: KeyEquivalent, enabled: Bool) -> some View {
        Button {
            vm.stepGallery(delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .disabled(!enabled)
        .opacity(enabled ? 0.9 : 0.2)
    }

    private func galleryInfo(_ item: RemoteItem?, position: Int?, total: Int) -> some View {
        HStack(spacing: 6) {
            if let item {
                Text(item.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("· \(item.isDirectory ? "—" : formattedSize(item.size)) · \(item.modified)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let position {
                Text("\(position + 1) of \(total)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func filmstrip(_ shown: [RemoteItem], serial: String, currentID: RemoteItem.ID?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(shown) { item in
                        filmCell(item, serial: serial, selected: item.id == currentID)
                            .id(item.id)
                    }
                }
                .padding(8)
            }
            .frame(height: 96)
            .onChange(of: currentID) { id in
                if let id {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func filmCell(_ item: RemoteItem, serial: String, selected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
            if item.kind == .image {
                RemoteImageView(serial: serial, item: item, maxPixel: thumbPixels, contentMode: .fill)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: item.symbolName)
                    .font(.system(size: 28))
                    .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
            }
        }
        .frame(width: 76, height: 76)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { vm.open(ids: [item.id]) }
        .onTapGesture { vm.selection = [item.id] }
        .help(item.name)
    }

    // MARK: - Status bar

    private func statusBar(_ shown: [RemoteItem]) -> some View {
        HStack(spacing: 12) {
            Text(statusText(shown))
                .foregroundStyle(.secondary)
            Spacer()
            if vm.viewMode == .grid {
                Image(systemName: "square.grid.3x3")
                    .foregroundStyle(.secondary)
                Slider(value: $vm.thumbSize, in: 80...260)
                    .frame(width: 130)
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.secondary)
            }
            if vm.viewMode != .gallery {
                Toggle("Previews", isOn: $vm.showPreview)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Menu {
                Button("Clear Preview Cache") { vm.clearPreviewCache() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func statusText(_ shown: [RemoteItem]) -> String {
        var text = "\(shown.count) \(shown.count == 1 ? "item" : "items")"
        if shown.count != vm.items.count {
            text += " (of \(vm.items.count))"
        }
        let selected = vm.selectedItems.count
        if selected > 0 {
            text += " · \(selected) selected"
        }
        return text
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { vm.goUp() } label: { Image(systemName: "chevron.up") }
                .help("Enclosing folder")
                .disabled(vm.path == "/")
            Button { vm.load() } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
        }
        ToolbarItemGroup {
            Picker("View", selection: $vm.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("List, grid or gallery")

            Menu {
                Picker("Show", selection: $vm.filter) {
                    ForEach(ItemFilter.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Filter by Kind",
                      systemImage: vm.filter == .all
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
            }
            .help("Show only one kind of item")

            Menu {
                sortButton("Name", \RemoteItem.sortName)
                sortButton("Size", \RemoteItem.size)
                sortButton("Kind", \RemoteItem.typeLabel)
                sortButton("Date Modified", \RemoteItem.modified)
                Divider()
                Toggle("Folders First", isOn: $vm.foldersFirst)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort items (in the list you can also click the column headers)")

            Button { vm.uploadWithPanel() } label: {
                Label("Send", systemImage: "square.and.arrow.up")
            }
            .help("Send files to the phone (you can also drag them into the window)")

            Button { vm.downloadSelectionWithPanel() } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
            .help("Download the selected items to the Mac")
            .disabled(vm.selection.isEmpty)

            Button { vm.newFolder() } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

            Button { vm.deleteSelection() } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(vm.selection.isEmpty)
        }
    }

    private func sortButton<V: Comparable>(_ title: String, _ keyPath: KeyPath<RemoteItem, V>) -> some View {
        Button {
            vm.sort(by: keyPath)
        } label: {
            if vm.isSorted(by: keyPath) {
                Label("\(title)  \(vm.sortAscending ? "↑" : "↓")", systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Drag & drop (Mac → phone)

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let collector = URLCollector()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.add(url)
                } else if let url = item as? URL {
                    collector.add(url)
                }
            }
        }
        group.notify(queue: .main) {
            let urls = collector.all()
            Task { @MainActor in
                vm.upload(urls)
            }
        }
        return true
    }
}

/// Collects URLs from the callbacks (which may arrive on different threads).
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func add(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func all() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

// MARK: - Status screens

struct AdbMissingView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("adb is not installed")
                .font(.title2.bold())
            Text("DroidBridge uses Android Debug Bridge to talk to the phone.\nInstall it from Terminal with:")
                .multilineTextAlignment(.center)
            Text("brew install android-platform-tools")
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)
            Text("Or download Platform-Tools from Google and copy the adb file to /usr/local/bin.")
                .foregroundStyle(.secondary)
            Text("Then reopen the app.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoDeviceView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
            Text("Connect your Android phone")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("1. On the phone: Settings → About phone → tap “Build number” 7 times.")
                Text("2. Settings → Developer options → turn on “USB debugging”.")
                Text("3. Plug in the USB cable and accept the “Allow USB debugging” prompt.")
            }
            .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
