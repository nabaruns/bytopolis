import Foundation

/// A single entry produced by scanning a path — either the scanned target itself
/// (the "total") or one of its immediate children.
struct DiskItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let byteSize: Int64
    let isDirectory: Bool

    var name: String { url.lastPathComponent }
    var path: String { url.path }

    /// Human-readable size, e.g. "1.2 GB" — the `-h` style, formatted in-app.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}
