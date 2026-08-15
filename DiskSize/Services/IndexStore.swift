import Foundation
import CryptoKit

/// Persists `ScanIndex` values across launches under Application Support.
///
/// Each index is one JSON file named by a hash of its root path. A small
/// `manifest.json` maps roots → files (and scan dates) so `findContaining` can
/// pick the right cache without decoding every (potentially large) index file.
enum IndexStore {

    struct ManifestEntry: Codable {
        let root: String
        let builtAt: Date
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
        manifest.append(ManifestEntry(root: index.root, builtAt: index.builtAt, file: file))
        saveManifest(manifest)
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
    static func findContaining(_ path: String) -> ScanIndex? {
        let std = DiskScanner.standardize(path)
        let candidates = loadManifest()
            .filter { entry in
                std == entry.root || std.hasPrefix(entry.root == "/" ? "/" : entry.root + "/")
            }
            .sorted { $0.root.count > $1.root.count }   // deepest root first

        for entry in candidates {
            if let index = load(root: entry.root) { return index }
        }
        return nil
    }

    static func delete(root: String) {
        let std = DiskScanner.standardize(root)
        try? FileManager.default.removeItem(at: baseDir.appendingPathComponent(fileName(forRoot: std)))
        saveManifest(loadManifest().filter { $0.root != std })
    }
}
