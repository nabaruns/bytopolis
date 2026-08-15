import Foundation
import CryptoKit

/// Persists `ScanIndex` values across launches under Application Support.
///
/// Each index is one JSON file named by a hash of its root path. A small
/// `manifest.json` maps roots → files (with size and last-access time) so
/// `findContaining` can pick the right cache without decoding every (potentially
/// large) index file, and so the cache can be capped and evicted.
enum IndexStore {

    // Eviction limits (least-recently-accessed evicted first).
    static let maxTotalBytes: Int64 = 100 * 1024 * 1024   // 100 MB of indexes
    static let maxEntries = 50
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60    // 30 days since last use

    struct ManifestEntry: Codable {
        let root: String
        let builtAt: Date
        var lastAccess: Date
        var fileSize: Int64
        let file: String
    }

    // MARK: - Locations

    private static var baseDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("DiskSize", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var manifestURL: URL { baseDir.appendingPathComponent("manifest.json") }

    private static func fileName(forRoot root: String) -> String {
        let digest = SHA256.hash(data: Data(root.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    // MARK: - Manifest

    private static func loadManifest() -> [ManifestEntry] {
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data)
        else { return [] }
        return entries
    }

    private static func saveManifest(_ entries: [ManifestEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    // MARK: - Public API

    static func save(_ index: ScanIndex) {
        let file = fileName(forRoot: index.root)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: baseDir.appendingPathComponent(file), options: .atomic)

        var manifest = loadManifest().filter { $0.root != index.root }
        manifest.append(ManifestEntry(root: index.root, builtAt: index.builtAt,
                                      lastAccess: Date(), fileSize: Int64(data.count), file: file))
        saveManifest(prune(manifest))
    }

    static func load(root: String) -> ScanIndex? {
        let std = DiskScanner.standardize(root)
        let url = baseDir.appendingPathComponent(fileName(forRoot: std))
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(ScanIndex.self, from: data)
        else { return nil }
        return index
    }

    /// The most specific (deepest-rooted) persisted index that contains `path`.
    /// Bumps that index's last-access time so it survives eviction.
    static func findContaining(_ path: String) -> ScanIndex? {
        let std = DiskScanner.standardize(path)
        let candidates = loadManifest()
            .filter { entry in
                std == entry.root || std.hasPrefix(entry.root == "/" ? "/" : entry.root + "/")
            }
            .sorted { $0.root.count > $1.root.count }   // deepest root first

        for entry in candidates {
            if let index = load(root: entry.root) {
                touch(root: entry.root)
                return index
            }
        }
        return nil
    }

    static func delete(root: String) {
        let std = DiskScanner.standardize(root)
        try? FileManager.default.removeItem(at: baseDir.appendingPathComponent(fileName(forRoot: std)))
        saveManifest(loadManifest().filter { $0.root != std })
    }

    /// Total bytes currently used by persisted indexes.
    static func totalBytes() -> Int64 { loadManifest().reduce(0) { $0 + $1.fileSize } }

    /// Number of persisted indexes (for diagnostics/tests).
    static func count() -> Int { loadManifest().count }

    // MARK: - Eviction

    private static func touch(root: String) {
        var manifest = loadManifest()
        guard let i = manifest.firstIndex(where: { $0.root == root }) else { return }
        manifest[i].lastAccess = Date()
        saveManifest(manifest)
    }

    /// Enforce the cache limits: drop orphans, then entries unused past `maxAge`,
    /// then the least-recently-accessed until under the size and count caps.
    /// Returns the surviving entries and deletes the evicted files.
    private static func prune(_ input: [ManifestEntry]) -> [ManifestEntry] {
        let fm = FileManager.default
        let now = Date()

        // Drop orphaned entries whose file is gone.
        var entries = input.filter { fm.fileExists(atPath: baseDir.appendingPathComponent($0.file).path) }

        var evicted: [ManifestEntry] = []

        // Age-out.
        entries.removeAll { entry in
            if now.timeIntervalSince(entry.lastAccess) > maxAge { evicted.append(entry); return true }
            return false
        }

        // Size / count cap: keep most-recently-accessed first.
        entries.sort { $0.lastAccess > $1.lastAccess }
        var kept: [ManifestEntry] = []
        var running: Int64 = 0
        for entry in entries {
            let withinCount = kept.count < maxEntries
            let withinSize = running + entry.fileSize <= maxTotalBytes
            // Always keep at least one entry so a single large index isn't unusable.
            if (withinCount && withinSize) || kept.isEmpty {
                kept.append(entry)
                running += entry.fileSize
            } else {
                evicted.append(entry)
            }
        }

        for entry in evicted {
            try? fm.removeItem(at: baseDir.appendingPathComponent(entry.file))
        }
        return kept
    }
}
