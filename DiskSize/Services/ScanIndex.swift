import Foundation

/// An in-memory index of a single full scan.
///
/// A `du -k <root>` (no depth limit) walks the whole subtree and reports the size
/// of every directory in it — for the same disk cost as a one-level scan. We keep
/// those sizes here so that browsing into any descendant (or back up to the root)
/// is instant, with no second `du` run. Individual file sizes aren't stored: they
/// come cheaply from the filesystem (`stat`) on demand when a folder is shown.
struct ScanIndex {
    let root: String                    // standardized absolute path
    let builtAt: Date
    let dirSizes: [String: Int64]       // standardized dir path -> bytes
    let partial: Bool                   // du hit permission errors during the scan

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
