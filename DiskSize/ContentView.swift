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

    private var scanTask: Task<Void, Never>?

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
            scan(asAdmin: false)
        }
    }

    /// Double-click / Return on a row: drill into folders, reveal files.
    func open(_ item: DiskItem) {
        if item.isDirectory {
            targetPath = item.path
            scan(asAdmin: false)
        } else {
            reveal(item)
        }
    }

    func reveal(_ item: DiskItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    var canGoUp: Bool {
        guard !targetPath.isEmpty else { return false }
        let parent = URL(fileURLWithPath: targetPath).deletingLastPathComponent().path
        return parent != targetPath && !targetPath.isEmpty && targetPath != "/"
    }

    func goUp() {
        guard canGoUp else { return }
        targetPath = URL(fileURLWithPath: targetPath).deletingLastPathComponent().path
        scan(asAdmin: false)
    }

    // MARK: - Scanning (two-phase)

    func scan(asAdmin: Bool) {
        let path = targetPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        scanTask?.cancel()
        errorMessage = nil
        total = nil
        partial = false

        // Phase 1: instant listing so the folder's contents appear immediately.
        children = Self.quickList(path: path)
        sizesPending = true

        // Phase 2: du computes real sizes off the main thread.
        scanTask = Task {
            let outcome: Result<ScanResult, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let result = asAdmin
                        ? try DiskScanner.scanAsAdmin(path: path)
                        : try DiskScanner.scan(path: path)
                    return .success(result)
                } catch {
                    return .failure(error)
                }
            }.value

            if Task.isCancelled { return }

            sizesPending = false
            switch outcome {
            case .success(let result):
                total = result.target
                children = result.children      // now with sizes, sorted largest-first
                partial = result.partial
            case .failure(let error):
                errorMessage = error.localizedDescription
                // Keep the phase-1 listing so the user still sees the folder.
            }
        }
    }

    /// Fast, best-effort immediate children via FileManager (no sizes yet).
    private static func quickList(path: String) -> [DiskItem] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return [] }
        let dir = URL(fileURLWithPath: path)
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]   // includes hidden files, like du
        ) else { return [] }

        return entries.map { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return DiskItem(url: url, byteSize: 0, isDirectory: isDirectory, sizeKnown: false)
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
                scan(asAdmin: false)   // refresh totals + list
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
        }
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
                .onSubmit { model.scan(asAdmin: false) }

            Button("Rescan") { model.scan(asAdmin: false) }
                .disabled(model.targetPath.isEmpty)

            Button("As Admin") { model.scan(asAdmin: true) }
                .disabled(model.targetPath.isEmpty)
                .help("Rescan with administrator privileges")
        }
        .padding(10)
    }

    @ViewBuilder
    private var header: some View {
        if !model.targetPath.isEmpty && (model.total != nil || model.sizesPending) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.total?.path ?? model.targetPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        if let total = model.total {
                            Text(total.formattedSize).font(.title2).bold()
                        } else {
                            Text("Calculating…").font(.title2).foregroundStyle(.secondary)
                        }
                    }
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
                .width(min: 140, ideal: 180)

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
