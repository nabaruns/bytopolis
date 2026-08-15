import Foundation

/// An index of a single full scan, held in memory and persisted to disk.
///
/// A `du -k <root>` (no depth limit) walks the whole subtree and reports the size
/// of every directory in it — for the same disk cost as a one-level scan. We keep
/// those sizes here so browsing into any descendant (or back up to the root) is
/// instant, with no second `du` run. Individual file sizes aren't stored: they
/// come cheaply from the filesystem (`stat`) on demand when a folder is shown.
///
/// `dirMTimes` records each directory's modification date so a later run can find
/// the changed subtrees and refresh only those (see `IncrementalScanner`).
struct ScanIndex: Codable {
    let root: String                    // standardized absolute path
    var builtAt: Date
    var dirSizes: [String: Int64]       // standardized dir path -> bytes
    var dirMTimes: [String: Date]       // standardized dir path -> mtime at scan
    var partial: Bool                   // du hit permission errors during the scan

    /// Is `path` the root or somewhere beneath it (so we can serve it from cache)?
    func contains(_ path: String) -> Bool {
        let p = DiskScanner.standardize(path)
        if p == root { return true }
        let prefix = root == "/" ? "/" : root + "/"
        return p.hasPrefix(prefix)
    }

    func dirSize(_ path: String) -> Int64? {
        dirSizes[DiskScanner.standardize(path)]
    }
}
