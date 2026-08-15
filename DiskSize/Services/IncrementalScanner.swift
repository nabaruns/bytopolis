import Foundation

/// Refreshes a cached `ScanIndex` by re-scanning only what changed.
///
/// A directory's mtime changes when its immediate entries are added, removed, or
/// renamed. So we stat every indexed directory (cheap — directories are far fewer
/// than files), find the ones whose mtime moved, reduce them to the minimal set of
/// changed subtree roots, and re-run `du` on just those. Size deltas are propagated
/// up each changed root's ancestors so parent totals stay correct.
///
/// Known limitation of any mtime-based scheme: editing a file *in place* (its bytes
/// change but no directory entry is added/removed) does not move any directory's
/// mtime, so that size change is missed until a full **Rescan**. This is the same
/// trade-off incremental backup tools make; it's why Rescan (full `du`) still exists.
enum IncrementalScanner {

    struct RefreshResult {
        let index: ScanIndex
        let changedRoots: [String]   // subtrees actually re-scanned (empty = nothing changed)
    }

    static func refresh(cache: ScanIndex, asAdmin: Bool) throws -> RefreshResult {
        // 1. Which indexed directories changed (or vanished)?
        var dirty = Set<String>()
        for dir in cache.dirSizes.keys {
            guard let old = cache.dirMTimes[dir] else { dirty.insert(dir); continue }
            let now = DiskScanner.mtime(dir)
            if now == nil || now! != old { dirty.insert(dir) }
        }

        if dirty.isEmpty {
            var idx = cache
            idx.builtAt = Date()          // verified fresh as of now
            return RefreshResult(index: idx, changedRoots: [])
        }

        // 2. Reduce to minimal changed roots (drop any dir that has a dirty ancestor).
        let roots = minimalRoots(dirty, under: cache.root)

        // 3. Start from the cached maps; replace each changed subtree, fix ancestors.
        var sizes = cache.dirSizes
        var mtimes = cache.dirMTimes
        var partial = cache.partial

        for r in roots.sorted() {
            let oldSize = sizes[r] ?? 0

            // Drop the stale subtree (root inclusive).
            let prefix = r == "/" ? "/" : r + "/"
            for key in Array(sizes.keys) where key == r || key.hasPrefix(prefix) {
                sizes[key] = nil
                mtimes[key] = nil
            }

            var newSize: Int64 = 0
            if FileManager.default.fileExists(atPath: r) {
                let sub = asAdmin
                    ? try DiskScanner.fullScanAsAdmin(path: r)
                    : try DiskScanner.fullScan(path: r)
                for (k, v) in sub.dirSizes { sizes[k] = v }
                for (k, v) in sub.dirMTimes { mtimes[k] = v }
                if sub.partial { partial = true }
                newSize = sub.dirSizes[r] ?? 0
            }
            // else: `r` was deleted — leave it and its subtree removed.

            // Propagate the size change up to (but not including) each ancestor's
            // own recompute — ancestors above a changed root are otherwise unchanged.
            let delta = newSize - oldSize
            if delta != 0 {
                for ancestor in ancestors(of: r, upTo: cache.root) {
                    sizes[ancestor, default: 0] += delta
                }
            }
        }

        let idx = ScanIndex(root: cache.root, builtAt: Date(),
                            dirSizes: sizes, dirMTimes: mtimes, partial: partial)
        return RefreshResult(index: idx, changedRoots: roots.sorted())
    }

    // MARK: - Path helpers

    /// Dirs in `dirty` that have no dirty ancestor within the scanned root.
    private static func minimalRoots(_ dirty: Set<String>, under root: String) -> [String] {
        dirty.filter { dir in
            for ancestor in ancestors(of: dir, upTo: root) where dirty.contains(ancestor) {
                return false
            }
            return true
        }
    }

    /// Ancestor directories of `path` from its parent up to and including `root`.
    private static func ancestors(of path: String, upTo root: String) -> [String] {
        guard path != root else { return [] }
        var result: [String] = []
        var current = path
        while true {
            let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path
            if parent == current { break }           // reached "/"
            result.append(parent)
            if parent == root { break }
            current = parent
        }
        return result
    }
}
