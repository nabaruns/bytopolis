import Foundation
import CoreGraphics

/// One element of the "software city": a district (folder), a building (file), or a
/// facility (a folder that is a git repo). Positions are in world XZ; the root plot is
/// `rootSide × rootSide` at the origin.
struct CityNode: Identifiable {
    enum Kind { case district, building, facility }
    let id: String            // path
    let name: String
    let rect: CGRect          // footprint (XZ)
    let depth: Int
    let byteSize: Int64
    let height: Double        // building height; 0 for districts/facilities
    let kind: Kind
    let category: ReclaimCategory?
    let mtime: Date?
    var isRecent: Bool
    var isEntry: Bool
    let git: GitInfo?
}

struct CityLayout {
    let nodes: [CityNode]
    let bounds: CGRect
    let truncated: Bool
}

enum CityModel {
    static let maxDepth = 4
    static let maxNodes = 1500
    static let minPlot: CGFloat = 6        // stop recursing below this footprint side
    static let rootSide: CGFloat = 200
    static let recentCount = 14            // brightest N leaves by mtime

    struct Entry {
        let path: String, name: String
        let isDir: Bool
        let byteSize: Int64
        let mtime: Date?
        let category: ReclaimCategory?
    }

    static func build(root: String, index: ScanIndex?, now: Date) -> CityLayout {
        var nodes: [CityNode] = []
        var truncated = false
        let rootRect = CGRect(x: 0, y: 0, width: rootSide, height: rootSide)

        func addChildren(dir: String, rect: CGRect, depth: Int) {
            if depth >= maxDepth || nodes.count >= maxNodes { truncated = true; return }
            let entries = children(of: dir, index: index)
            guard !entries.isEmpty else { return }

            let inner = rect.insetBy(dx: rect.width * 0.05 + 1, dy: rect.height * 0.05 + 1)
            guard inner.width > 1, inner.height > 1 else { return }
            let tiles = Squarify.layout(items: entries.map { ($0.path, Double(max($0.byteSize, 1))) },
                                        in: inner)

            for entry in entries {
                if nodes.count >= maxNodes { truncated = true; break }
                guard let r = tiles[entry.path], r.width > 0.5, r.height > 0.5 else { continue }

                if entry.isDir {
                    let git = GitReader.info(entry.path)
                    nodes.append(CityNode(
                        id: entry.path, name: entry.name, rect: r, depth: depth,
                        byteSize: entry.byteSize, height: 0,
                        kind: git != nil ? .facility : .district,
                        category: entry.category, mtime: entry.mtime,
                        isRecent: false, isEntry: false, git: git))
                    if min(r.width, r.height) > minPlot {
                        addChildren(dir: entry.path, rect: r, depth: depth + 1)
                    }
                } else {
                    nodes.append(CityNode(
                        id: entry.path, name: entry.name, rect: r, depth: depth,
                        byteSize: entry.byteSize, height: buildingHeight(entry.byteSize),
                        kind: .building, category: entry.category, mtime: entry.mtime,
                        isRecent: false, isEntry: false, git: nil))
                }
            }
        }

        addChildren(dir: root, rect: rootRect, depth: 0)
        markRecent(&nodes)
        return CityLayout(nodes: nodes, bounds: rootRect, truncated: truncated)
    }

    /// Building height on a gentle log scale (KB → world units), capped.
    static func buildingHeight(_ bytes: Int64) -> Double {
        let kb = Double(max(bytes, 1024)) / 1024
        return min(42, 0.8 + 2.2 * log10(kb))
    }

    /// Immediate children with sizes: dirs from the index, files from the filesystem.
    static func children(of dir: String, index: ScanIndex?) -> [Entry] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey
        ]
        guard let urls = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: dir), includingPropertiesForKeys: Array(keys),
            options: [.skipsSubdirectoryDescendants]) else { return [] }

        var result: [Entry] = []
        for url in urls {
            let vals = try? url.resourceValues(forKeys: keys)
            let isDir = vals?.isDirectory ?? false
            let mtime = vals?.contentModificationDate
            let category = ReclaimRules.classify(url: url, isDirectory: isDir)
            let size: Int64
            if isDir {
                size = index?.dirSize(url.path) ?? 0
            } else {
                size = Int64(vals?.totalFileAllocatedSize ?? vals?.fileAllocatedSize ?? 0)
            }
            result.append(Entry(path: url.path, name: url.lastPathComponent,
                                isDir: isDir, byteSize: size, mtime: mtime, category: category))
        }
        return result
    }

    /// Light up the most-recently-modified nodes; the single newest is the "entry".
    private static func markRecent(_ nodes: inout [CityNode]) {
        let ranked = nodes.enumerated()
            .compactMap { idx, n in n.mtime.map { (idx, $0) } }
            .sorted { $0.1 > $1.1 }
        for (rank, pair) in ranked.enumerated() where rank < recentCount {
            nodes[pair.0].isRecent = true
        }
        if let entry = ranked.first { nodes[entry.0].isEntry = true }
    }
}
