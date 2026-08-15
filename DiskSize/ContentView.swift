import SwiftUI
import AppKit

@MainActor
final class ScanModel: ObservableObject {
    @Published var targetPath: String = ""
    @Published var total: DiskItem?
    @Published var children: [DiskItem] = []
    @Published var isScanning = false
    @Published var partial = false          // du hit permission errors
    @Published var errorMessage: String?
    @Published var sortOrder: [KeyPathComparator<DiskItem>] = [
        .init(\.byteSize, order: .reverse)
    ]

    private var scanTask: Task<Void, Never>?

    var sortedChildren: [DiskItem] {
        children.sorted(using: sortOrder)
    }

    var largest: Int64 { children.map(\.byteSize).max() ?? 0 }

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

    func scan(asAdmin: Bool) {
        let path = targetPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        scanTask?.cancel()
        isScanning = true
        errorMessage = nil

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

            isScanning = false
            switch outcome {
            case .success(let result):
                total = result.target
                children = result.children
                partial = result.partial
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ item: DiskItem, asAdmin: Bool) {
        errorMessage = nil
        Task {
            let outcome: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    if asAdmin {
                        try Deleter.removeAsAdmin(path: item.path)
                    } else {
                        try Deleter.remove(path: item.path)
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
    @State private var pendingDelete: DiskItem?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            header
            content
        }
        .confirmationDialog(
            "Permanently delete this item?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingDelete {
                Button("Delete \(item.formattedSize) — rm -rf", role: .destructive) {
                    model.delete(item, asAdmin: false)
                    pendingDelete = nil
                }
                Button("Delete as Administrator", role: .destructive) {
                    model.delete(item, asAdmin: true)
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
        } message: {
            if let item = pendingDelete {
                Text("\(item.path)\n\nThis runs rm -rf and cannot be undone.")
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
        if let total = model.total {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(total.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(total.formattedSize)
                        .font(.title2).bold()
                }
                Spacer()
                if model.isScanning { ProgressView().controlSize(.small) }
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
        if model.total == nil && model.isScanning {
            Spacer()
            ProgressView("Scanning…")
            Spacer()
        } else if model.total == nil {
            Spacer()
            ContentUnavailableCompat(
                title: "No folder selected",
                subtitle: "Choose a folder or file to see what's using space.",
                systemImage: "internaldrive"
            )
            Spacer()
        } else {
            Table(model.sortedChildren, sortOrder: $model.sortOrder) {
                TableColumn("Name") { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(item.isDirectory ? .blue : .secondary)
                        Text(item.name).lineLimit(1)
                    }
                }
                .width(min: 160, ideal: 260)

                TableColumn("Size", value: \.byteSize) { item in
                    ProportionCell(size: item.byteSize,
                                   largest: model.largest,
                                   label: item.formattedSize)
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
