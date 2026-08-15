import SwiftUI
import AppKit

@MainActor
final class ScanModel: ObservableObject {
    @Published var targetPath: String = ""
    @Published var total: DiskItem?
    @Published var children: [DiskItem] = []
    @Published var sizesPending = false     // list is shown, du still computing sizes
    @Published var partial = false          // du hit permission errors
    @Published var errorMessage: String?
    @Published var sortOrder: [KeyPathComparator<DiskItem>] = [
        .init(\.byteSize, order: .reverse)
    ]

    // Indexing / cache state
    @Published var servedFromIndex = false  // current view came from the cached index
    @Published var indexBuiltAt: Date?      // when the active index was scanned
    @Published var stale = false            // shown folder changed on disk since the scan
    @Published var refreshing = false       // background incremental refresh in progress

    // Per-folder item counts (filled in the background so browsing stays instant).
    @Published var childCounts: [DiskItem.ID: Int] = [:]

    // On-disk cache stats
    @Published var cacheBytes: Int64 = 0
    @Published var cacheCount: Int = 0

    private var index: ScanIndex?
    private var scanTask: Task<Void, Never>?
    private var countTask: Task<Void, Never>?

    var sortedChildren: [DiskItem] {
        if sizesPending {
            // No sizes yet — show folders first, then alphabetical.
            return children.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        return children.sorted(using: sortOrder)
    }

    var largest: Int64 { children.filter(\.sizeKnown).map(\.byteSize).max() ?? 0 }

    func item(id: DiskItem.ID) -> DiskItem? { children.first { $0.id == id } }

    // MARK: - Navigation

    func chooseTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            targetPath = url.path
            scan()
        }
    }

    /// Double-click / Return on a row: drill into folders, reveal files.
    func open(_ item: DiskItem) {
        if item.isDirectory {
            targetPath = item.path
            scan()                      // instant when inside the current index
        } else {
            reveal(item)
        }
    }

    func reveal(_ item: DiskItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    var canGoUp: Bool {
        let p = DiskScanner.standardize(targetPath.trimmingCharacters(in: .whitespaces))
        return !p.isEmpty && p != "/"
    }

    func goUp() {
        guard canGoUp else { return }
        targetPath = URL(fileURLWithPath: DiskScanner.standardize(targetPath)).deletingLastPathComponent().path
        scan()
    }

    // MARK: - Scanning (index-backed, persisted)

    /// Browse `targetPath`. Order of preference:
    ///   1. In-memory index that contains the path — instant.
    ///   2. Persisted (on-disk) index that contains the path — instant, then an
    ///      incremental refresh runs in the background to catch changes.
    ///   3. A fresh full `du` scan, which is then persisted.
    func scan(asAdmin: Bool = false, force: Bool = false) {
        let expanded = (targetPath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        let path = DiskScanner.standardize(expanded)
        guard !path.isEmpty else { return }
        targetPath = path               // reflect the resolved absolute path

        scanTask?.cancel()
        errorMessage = nil

        // 1. In-memory cache hit — no du needed.
        if !force, !asAdmin, let idx = index, idx.contains(path) {
            present(path: path, from: idx, servedFromIndex: true)
            if stale { refreshInBackground(showing: path) }
            return
        }

        total = nil
        partial = false
        servedFromIndex = false
        children = Self.quickList(path: path)
        sizesPending = true

        scanTask = Task {
            // 2. Persisted cache hit — show instantly, then refresh in the background.
            if !force, !asAdmin,
               let disk = await Task.detached(priority: .userInitiated, operation: {
                   IndexStore.findContaining(path)
               }).value {
                if Task.isCancelled { return }
                index = disk
                sizesPending = false
                present(path: path, from: disk, servedFromIndex: true)
                refreshInBackground(showing: path)
                return
            }

            // 3. Fresh full scan.
            let outcome: Result<FullScanResult, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let r = asAdmin
                        ? try DiskScanner.fullScanAsAdmin(path: path)
                        : try DiskScanner.fullScan(path: path)
                    return .success(r)
                } catch {
                    return .failure(error)
                }
            }.value

            if Task.isCancelled { return }
            sizesPending = false

            switch outcome {
            case .success(let r):
                let idx = ScanIndex(root: r.root, builtAt: Date(),
                                    dirSizes: r.dirSizes, dirMTimes: r.dirMTimes, partial: r.partial)
                index = idx
                present(path: path, from: idx, servedFromIndex: false)
                persist(idx)
            case .failure(let error):
                errorMessage = error.localizedDescription
                // Keep the phase-1 listing so the user still sees the folder.
            }
        }
    }

    /// Re-scan only the changed subtrees of the active index, off the main thread,
    /// then update the view and persist the fresher index.
    private func refreshInBackground(showing path: String) {
        guard let cache = index, !refreshing else { return }
        refreshing = true
        Task {
            let refreshed = await Task.detached(priority: .utility) { () -> ScanIndex? in
                try? IncrementalScanner.refresh(cache: cache, asAdmin: false).index
            }.value

            refreshing = false
            guard let refreshed, !Task.isCancelled else { return }
            index = refreshed
            persist(refreshed)
            // Re-present if the user is still looking at a folder in this index.
            let current = DiskScanner.standardize(targetPath)
            if refreshed.contains(current) {
                present(path: current, from: refreshed, servedFromIndex: true)
            }
        }
    }

    private func persist(_ idx: ScanIndex) {
        Task {
            await Task.detached(priority: .background) { IndexStore.save(idx) }.value
            refreshCacheStats()
        }
    }

    /// Build the visible rows for `path` from the index (dir sizes) plus the
    /// filesystem (file sizes + directory listing). No `du` involved.
    private func present(path: String, from idx: ScanIndex, servedFromIndex: Bool) {
        let fm = FileManager.default
        let std = DiskScanner.standardize(path)
        let dirURL = URL(fileURLWithPath: std)

        var isDir: ObjCBool = false
        fm.fileExists(atPath: std, isDirectory: &isDir)
        let totalVals = try? dirURL.resourceValues(forKeys: Self.dateKeys)

        total = DiskItem(url: dirURL,
                         byteSize: idx.dirSize(std) ?? 0,
                         isDirectory: isDir.boolValue,
                         sizeKnown: idx.dirSize(std) != nil,
                         modified: totalVals?.contentModificationDate,
                         created: totalVals?.creationDate)

        var items: [DiskItem] = []
        if let entries = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: Array(Self.rowKeys),
            options: [.skipsSubdirectoryDescendants]
        ) {
            for url in entries {
                let vals = try? url.resourceValues(forKeys: Self.rowKeys)
                let isDirectory = vals?.isDirectory ?? false
                let modified = vals?.contentModificationDate
                let created = vals?.creationDate
                if isDirectory {
                    let size = idx.dirSize(url.path)
                    items.append(DiskItem(url: url, byteSize: size ?? 0,
                                          isDirectory: true, sizeKnown: size != nil,
                                          modified: modified, created: created))
                } else {
                    let bytes = vals?.totalFileAllocatedSize ?? vals?.fileAllocatedSize ?? 0
                    items.append(DiskItem(url: url, byteSize: Int64(bytes),
                                          isDirectory: false, sizeKnown: true,
                                          modified: modified, created: created))
                }
            }
        }

        children = items
        partial = idx.partial
        self.servedFromIndex = servedFromIndex
        indexBuiltAt = idx.builtAt
        stale = Self.modifiedAfter(std, date: idx.builtAt)
        fillChildCounts(for: items)
    }

    /// Count each folder's immediate entries off the main thread, then publish.
    private func fillChildCounts(for items: [DiskItem]) {
        countTask?.cancel()
        childCounts = [:]
        let dirs = items.filter(\.isDirectory).map { ($0.id, $0.path) }
        guard !dirs.isEmpty else { return }
        countTask = Task {
            let counts = await Task.detached(priority: .utility) { () -> [DiskItem.ID: Int] in
                var result: [DiskItem.ID: Int] = [:]
                for (id, path) in dirs {
                    if Task.isCancelled { break }
                    let n = (try? FileManager.default.contentsOfDirectory(atPath: path))?.count
                    if let n { result[id] = n }
                }
                return result
            }.value
            if !Task.isCancelled { childCounts = counts }
        }
    }

    // MARK: - Cache stats

    func refreshCacheStats() {
        Task {
            let stats = await Task.detached(priority: .background) {
                (bytes: IndexStore.totalBytes(), count: IndexStore.count())
            }.value
            cacheBytes = stats.bytes
            cacheCount = stats.count
        }
    }

    func clearCache() {
        Task {
            await Task.detached(priority: .background) { IndexStore.clearAll() }.value
            refreshCacheStats()
        }
    }

    /// Has this directory been modified since the index was built?
    private static func modifiedAfter(_ path: String, date: Date) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return false }
        return mtime > date
    }

    /// Resource keys fetched per row (sizes + dates) and just dates for the header.
    private static let rowKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentModificationDateKey, .creationDateKey
    ]
    private static let dateKeys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]

    /// Fast, best-effort immediate children via FileManager (no sizes yet).
    private static func quickList(path: String) -> [DiskItem] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return [] }
        let dir = URL(fileURLWithPath: path)
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: Array(rowKeys),
            options: [.skipsSubdirectoryDescendants]   // includes hidden files, like du
        ) else { return [] }

        return entries.map { url in
            let vals = try? url.resourceValues(forKeys: rowKeys)
            return DiskItem(url: url, byteSize: 0,
                            isDirectory: vals?.isDirectory ?? false, sizeKnown: false,
                            modified: vals?.contentModificationDate, created: vals?.creationDate)
        }
    }

    // MARK: - Delete

    enum DeleteMode {
        case trash          // reversible, Finder Trash
        case permanent      // rm -rf
        case admin          // rm -rf with administrator privileges
    }

    func delete(_ item: DiskItem, mode: DeleteMode) {
        errorMessage = nil
        Task {
            let outcome: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    switch mode {
                    case .trash:     try Deleter.moveToTrash(path: item.path)
                    case .permanent: try Deleter.remove(path: item.path)
                    case .admin:     try Deleter.removeAsAdmin(path: item.path)
                    }
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value

            switch outcome {
            case .success:
                index = nil               // sizes changed — invalidate the index
                scan(force: true)         // rebuild + refresh
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ScanModel()
    @State private var selection: DiskItem.ID?
    @State private var pendingDelete: DiskItem?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            header
            content
            Divider()
            cacheFooter
        }
        .task { model.refreshCacheStats() }
        .confirmationDialog(
            "Delete this item?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingDelete {
                Button("Move to Trash") {
                    model.delete(item, mode: .trash)
                    pendingDelete = nil
                }
                Button("Delete Permanently \(item.formattedSize) — rm -rf", role: .destructive) {
                    model.delete(item, mode: .permanent)
                    pendingDelete = nil
                }
                Button("Delete Permanently as Administrator", role: .destructive) {
                    model.delete(item, mode: .admin)
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
        } message: {
            if let item = pendingDelete {
                Text("\(item.path)\n\nMove to Trash is reversible. Deleting permanently runs rm -rf and cannot be undone.")
            }
        }
    }

    // MARK: - Sections

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                model.chooseTarget()
            } label: {
                Label("Choose…", systemImage: "folder")
            }

            Button {
                model.goUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!model.canGoUp)
            .help("Go to parent folder")

            TextField("Path to scan", text: $model.targetPath)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.scan() }

            Button("Rescan") { model.scan(force: true) }
                .disabled(model.targetPath.isEmpty)
                .help("Discard the index and scan fresh")

            Button("As Admin") { model.scan(asAdmin: true) }
                .disabled(model.targetPath.isEmpty)
                .help("Rescan with administrator privileges")
        }
        .padding(10)
    }

    @ViewBuilder
    private var header: some View {
        if !model.targetPath.isEmpty && (model.total != nil || model.sizesPending) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.total?.path ?? model.targetPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let total = model.total {
                        Text(total.formattedSize).font(.title2).bold()
                    } else {
                        Text("Calculating…").font(.title2).foregroundStyle(.secondary)
                    }
                    indexStatus
                }
                Spacer()
                if model.sizesPending { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if model.partial {
                banner(
                    "Some items couldn't be read. Rescan as administrator for full sizes.",
                    icon: "lock.fill",
                    action: ("As Admin", { model.scan(asAdmin: true) })
                )
            }
        }

        if let error = model.errorMessage {
            banner(error, icon: "exclamationmark.triangle.fill", action: nil)
        }
    }

    @ViewBuilder
    private var indexStatus: some View {
        if let builtAt = model.indexBuiltAt, !model.sizesPending {
            HStack(spacing: 5) {
                Image(systemName: model.servedFromIndex ? "bolt.fill" : "clock.arrow.circlepath")
                    .foregroundStyle(model.servedFromIndex ? .green : .secondary)
                Text(model.servedFromIndex ? "Indexed" : "Scanned")
                Text(builtAt, style: .relative) + Text(" ago")
                if model.refreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                    Text("refreshing changed folders…").foregroundStyle(.secondary)
                } else if model.stale {
                    Text("· changed since scan").foregroundStyle(.orange)
                    Button("Rescan") { model.scan(force: true) }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.targetPath.isEmpty {
            Spacer()
            ContentUnavailableCompat(
                title: "No folder selected",
                subtitle: "Choose a folder or file to see what's using space.",
                systemImage: "internaldrive"
            )
            Spacer()
        } else {
            Table(model.sortedChildren, selection: $selection, sortOrder: $model.sortOrder) {
                TableColumn("Name") { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(item.isDirectory ? .blue : .secondary)
                        Text(item.name).lineLimit(1)
                    }
                }
                .width(min: 160, ideal: 260)

                TableColumn("Size", value: \.byteSize) { item in
                    if item.sizeKnown {
                        ProportionCell(size: item.byteSize,
                                       largest: model.largest,
                                       label: item.formattedSize)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 130, ideal: 170)

                TableColumn("Kind", value: \.kind) { item in
                    Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 70, ideal: 90)

                TableColumn("Modified", value: \.modifiedValue) { item in
                    Text(item.modifiedText).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Created", value: \.createdValue) { item in
                    Text(item.createdText).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Items") { item in
                    if item.isDirectory {
                        Text(model.childCounts[item.id].map(String.init) ?? "…")
                            .foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .width(min: 50, ideal: 64)

                TableColumn("") { item in
                    Button(role: .destructive) {
                        pendingDelete = item
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete \(item.path)")
                }
                .width(40)
            }
            .contextMenu(forSelectionType: DiskItem.ID.self) { ids in
                if let id = ids.first, let item = model.item(id: id) {
                    if item.isDirectory {
                        Button("Open") { model.open(item) }
                    }
                    Button("Reveal in Finder") { model.reveal(item) }
                    Divider()
                    Button("Delete…", role: .destructive) { pendingDelete = item }
                }
            } primaryAction: { ids in
                if let id = ids.first, let item = model.item(id: id) {
                    model.open(item)   // double-click / Return
                }
            }
        }
    }

    private var cacheFooter: some View {
        let used = ByteCountFormatter.string(fromByteCount: model.cacheBytes, countStyle: .file)
        let cap = ByteCountFormatter.string(fromByteCount: IndexStore.maxTotalBytes, countStyle: .file)
        return HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.timemachine")
                .foregroundStyle(.secondary)
            Text("Index cache: \(used) / \(cap) · \(model.cacheCount) \(model.cacheCount == 1 ? "root" : "roots")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear Cache") { model.clearCache() }
                .controlSize(.small)
                .disabled(model.cacheCount == 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func banner(_ text: String, icon: String, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text).font(.callout)
            Spacer()
            if let action {
                Button(action.0, action: action.1)
            }
        }
        .padding(8)
        .background(.yellow.opacity(0.15))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

/// A size cell with a subtle proportion bar behind the label.
private struct ProportionCell: View {
    let size: Int64
    let largest: Int64
    let label: String

    var fraction: Double {
        largest > 0 ? Double(size) / Double(largest) : 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.tint.opacity(0.18))
                    .frame(width: max(2, geo.size.width * fraction))
                Text(label)
                    .font(.callout).monospacedDigit()
                    .padding(.leading, 6)
            }
        }
        .frame(height: 18)
    }
}

/// Minimal stand-in so we don't depend on macOS 14's ContentUnavailableView.
private struct ContentUnavailableCompat: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
