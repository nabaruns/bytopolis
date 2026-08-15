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

    /// Path is a stable identity, so selection survives the phase-1 → phase-2 swap.
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var path: String { url.path }

    init(url: URL, byteSize: Int64, isDirectory: Bool, sizeKnown: Bool = true) {
        self.url = url
        self.byteSize = byteSize
        self.isDirectory = isDirectory
        self.sizeKnown = sizeKnown
    }

    /// Human-readable size, e.g. "1.2 GB" — the `-h` style, formatted in-app.
    /// Returns "—" while the size is still being computed.
    var formattedSize: String {
        guard sizeKnown else { return "—" }
        return ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}
