import Foundation

/// A single entry produced by scanning a path — either the scanned target itself
/// (the "total") or one of its immediate children.
///
/// `sizeKnown` is false during the instant phase-1 listing (children shown before
/// `du` has computed sizes) and true once the scan fills the real size in.
struct DiskItem: Identifiable, Hashable {
    let url: URL
    let byteSize: Int64
    let isDirectory: Bool
    let sizeKnown: Bool
    let modified: Date?
    let created: Date?
    let category: ReclaimCategory?

    /// Path is a stable identity, so selection survives the phase-1 → phase-2 swap.
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var path: String { url.path }

    init(url: URL, byteSize: Int64, isDirectory: Bool, sizeKnown: Bool = true,
         modified: Date? = nil, created: Date? = nil, category: ReclaimCategory? = nil) {
        self.url = url
        self.byteSize = byteSize
        self.isDirectory = isDirectory
        self.sizeKnown = sizeKnown
        self.modified = modified
        self.created = created
        self.category = category
    }

    var reclaim: Reclaimability { category?.reclaim ?? .keep }
    var categoryText: String { category?.name ?? "—" }
    var categorySort: Int { (category?.reclaim.priority ?? 3) }

    /// Human-readable size, e.g. "1.2 GB" — the `-h` style, formatted in-app.
    /// Returns "—" while the size is still being computed.
    var formattedSize: String {
        guard sizeKnown else { return "—" }
        return ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    var kind: String {
        if isDirectory { return "Folder" }
        let ext = url.pathExtension
        return ext.isEmpty ? "File" : ext.lowercased() + " file"
    }

    // Sortable keys (Optional isn't Comparable, so fall back to distantPast).
    var modifiedValue: Date { modified ?? .distantPast }
    var createdValue: Date { created ?? .distantPast }

    var modifiedText: String { Self.format(modified) }
    var createdText: String { Self.format(created) }

    private static func format(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
