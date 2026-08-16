import Foundation

/// Lightweight git metadata read straight from `.git` files (no shelling out).
struct GitInfo: Equatable {
    let branch: String?
    let remoteURL: String?
    var isGitHub: Bool { (remoteURL ?? "").contains("github.com") }
}

enum GitReader {
    /// A directory is a repo if it has a `.git` directory (or a `.git` file for worktrees).
    static func isRepo(_ path: String) -> Bool {
        let dotGit = (path as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir)
    }

    static func info(_ path: String) -> GitInfo? {
        guard isRepo(path) else { return nil }
        return GitInfo(branch: branch(path), remoteURL: remoteURL(path))
    }

    /// Parse the current branch from `.git/HEAD` (`ref: refs/heads/<branch>`).
    static func branch(_ path: String) -> String? {
        let head = (path as NSString).appendingPathComponent(".git/HEAD")
        guard let raw = try? String(contentsOfFile: head, encoding: .utf8) else { return nil }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref:") {
            return line.components(separatedBy: "refs/heads/").last
        }
        return String(line.prefix(7))   // detached HEAD → short sha
    }

    /// Parse the origin remote URL from `.git/config`.
    static func remoteURL(_ path: String) -> String? {
        let config = (path as NSString).appendingPathComponent(".git/config")
        guard let raw = try? String(contentsOfFile: config, encoding: .utf8) else { return nil }

        var inOrigin = false
        var firstRemote: String?
        for rawLine in raw.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[remote ") {
                inOrigin = line.contains("\"origin\"")
                continue
            }
            if line.hasPrefix("[") { inOrigin = false; continue }
            if line.hasPrefix("url = ") || line.hasPrefix("url=") {
                let url = line.components(separatedBy: "=").dropFirst().joined(separator: "=")
                    .trimmingCharacters(in: .whitespaces)
                if inOrigin { return url }
                if firstRemote == nil { firstRemote = url }
            }
        }
        return firstRemote
    }
}
