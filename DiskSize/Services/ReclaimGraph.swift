import Foundation

/// One reclaimable item surfaced to the UI and the LLM assistant.
struct ReclaimCandidate: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let byteSize: Int64
    let ageDays: Int?
    let category: ReclaimCategory
    let appName: String?          // set when the item belongs to a known app

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file) }
}

struct ReclaimSummary {
    let candidates: [ReclaimCandidate]   // reclaimable (safe + caution), largest first
    var reclaimableBytes: Int64 { candidates.reduce(0) { $0 + $1.byteSize } }
    var safeBytes: Int64 { candidates.filter { $0.category.reclaim == .safe }.reduce(0) { $0 + $1.byteSize } }
}

/// Builds the reclaim view over a scanned `ScanIndex`: classifies directories,
/// dedups nested matches (keep the top-most `node_modules`, not its children), and
/// attributes app-support paths to their owning app.
enum ReclaimGraph {

    /// Reclaimable candidates across the whole index, largest first.
    static func summary(index: ScanIndex, limit: Int = 300) -> ReclaimSummary {
        let now = Date()
        // Parent dirs first so we can cut descendants of an accepted candidate.
        let dirs = index.dirSizes.keys.sorted { $0.count < $1.count }
        var accepted: [String] = []
        var candidates: [ReclaimCandidate] = []
        let apps = appNameMap()

        for dir in dirs {
            // Skip anything already inside an accepted reclaimable directory.
            if accepted.contains(where: { dir == $0 || dir.hasPrefix($0 + "/") }) { continue }
            guard let cat = ReclaimRules.classify(url: URL(fileURLWithPath: dir), isDirectory: true),
                  cat.reclaim != .keep else { continue }

            accepted.append(dir)
            let age = index.dirMTimes[dir].map { Int(now.timeIntervalSince($0) / 86_400) }
            candidates.append(ReclaimCandidate(
                path: dir,
                byteSize: index.dirSizes[dir] ?? 0,
                ageDays: age,
                category: cat,
                appName: appName(forPath: dir, apps: apps)))
        }

        candidates.sort { $0.byteSize > $1.byteSize }
        return ReclaimSummary(candidates: Array(candidates.prefix(limit)))
    }

    /// Compact JSON of the top candidates for the LLM — metadata only, no contents.
    static func summaryJSON(index: ScanIndex, limit: Int = 40) -> String {
        let items = summary(index: index).candidates.prefix(limit).map { c -> [String: Any] in
            [
                "path": c.path,
                "sizeBytes": c.byteSize,
                "ageDays": c.ageDays as Any,
                "category": c.category.name,
                "reclaim": c.category.reclaim.rawValue
            ]
        }
        let payload: [String: Any] = [
            "root": index.root,
            "candidates": Array(items)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    // MARK: - App attribution

    /// bundleID -> app display name, from installed .app bundles.
    static func appNameMap() -> [String: String] {
        var map: [String: String] = [:]
        let fm = FileManager.default
        let dirs = ["/Applications",
                    fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let plist = "\(dir)/\(entry)/Contents/Info.plist"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: plist)),
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let bundleID = info["CFBundleIdentifier"] as? String else { continue }
                let display = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? String(entry.dropLast(4))
                map[bundleID] = display
            }
        }
        return map
    }

    /// If `path` is an app-support/cache/container path named by a bundle id, return
    /// the owning app's display name.
    static func appName(forPath path: String, apps: [String: String]) -> String? {
        let last = URL(fileURLWithPath: path).lastPathComponent
        if let name = apps[last] { return name }
        // Bundle ids can carry a suffix (e.g. com.foo.bar.helper); try trimming.
        var comps = last.split(separator: ".")
        while comps.count >= 3 {
            let candidate = comps.joined(separator: ".")
            if let name = apps[candidate] { return name }
            comps.removeLast()
        }
        return nil
    }
}
