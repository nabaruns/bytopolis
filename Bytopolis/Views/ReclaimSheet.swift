import SwiftUI

/// Lists reclaimable candidates (caches, build artifacts, dependency stores) across
/// the scanned tree, lets the user select some, and deletes them through the same
/// guarded `Deleter` path as everywhere else.
struct ReclaimSheet: View {
    @ObservedObject var model: ScanModel
    @Environment(\.dismiss) private var dismiss

    @State private var selection = Set<ReclaimCandidate.ID>()
    @State private var confirmMode: ScanModel.DeleteMode?

    private var candidates: [ReclaimCandidate] { model.reclaim?.candidates ?? [] }
    private var selected: [ReclaimCandidate] { candidates.filter { selection.contains($0.id) } }
    private var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.byteSize } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .confirmationDialog(
            "Delete \(selected.count) item\(selected.count == 1 ? "" : "s")?",
            isPresented: Binding(get: { confirmMode != nil }, set: { if !$0 { confirmMode = nil } }),
            titleVisibility: .visible
        ) {
            if let mode = confirmMode {
                Button(actionTitle(mode), role: mode == .trash ? nil : .destructive) {
                    model.deleteCandidates(selected, mode: mode)
                    selection.removeAll()
                    confirmMode = nil
                }
                Button("Cancel", role: .cancel) { confirmMode = nil }
            }
        } message: {
            Text("\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)) selected.\n"
                 + (confirmMode == .trash ? "Items move to the Trash (recoverable)."
                                          : "This runs rm -rf and cannot be undone."))
        }
    }

    private func actionTitle(_ mode: ScanModel.DeleteMode) -> String {
        switch mode {
        case .trash: return "Move to Trash"
        case .permanent: return "Delete Permanently"
        case .admin: return "Delete as Administrator"
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reclaim space").font(.title3).bold()
                if let summary = model.reclaim {
                    Text("Reclaimable: \(ByteCountFormatter.string(fromByteCount: summary.reclaimableBytes, countStyle: .file))  ·  Safe: \(ByteCountFormatter.string(fromByteCount: summary.safeBytes, countStyle: .file))  ·  \(summary.candidates.count) items")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Select Safe") {
                selection = Set(candidates.filter { $0.category.reclaim == .safe }.map(\.id))
            }
            Button("Clear") { selection.removeAll() }
                .disabled(selection.isEmpty)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if model.reclaimLoading {
            Spacer(); ProgressView("Analyzing…"); Spacer()
        } else if candidates.isEmpty {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(.secondary)
                Text("Nothing obvious to reclaim here.").foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            List(selection: $selection) {
                ForEach(candidates) { c in
                    HStack(spacing: 8) {
                        Circle().fill(c.category.reclaim.color).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(c.name).lineLimit(1)
                                if let app = c.appName {
                                    Text(app).font(.caption).foregroundStyle(.secondary)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                            Text(c.path).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(c.formattedSize).monospacedDigit()
                            Text(c.category.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([c.url])
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Selected: \(selected.count) · \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Move to Trash") { confirmMode = .trash }
                .disabled(selected.isEmpty)
            Button("Delete Permanently") { confirmMode = .permanent }
                .disabled(selected.isEmpty)
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}
