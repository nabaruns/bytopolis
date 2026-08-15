import Foundation

/// Outcome of a scan: the target total, its immediate children, and whether some
/// entries were unreadable (which the UI turns into an "escalate to admin" prompt).
struct ScanResult {
    let target: DiskItem
    let children: [DiskItem]
    let partial: Bool          // true if du reported permission errors
    let stderr: String
}

enum ScanError: Error, LocalizedError {
    case cancelledAuthorization
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelledAuthorization: return "Authorization cancelled."
        case .failed(let msg): return msg
        }
    }
}

/// Wraps `du -k -d1 <path>`. We use `-k` (numeric KB) rather than `-h` so sizes
/// sort correctly; the UI formats bytes to human units with ByteCountFormatter.
enum DiskScanner {

    /// Scan as the current user.
    static func scan(path: String) throws -> ScanResult {
        let result = Shell.run("/usr/bin/du", ["-k", "-d", "1", path])
        return try parse(result: result, targetPath: path)
    }

    /// Scan with administrator privileges (native auth prompt).
    static func scanAsAdmin(path: String) throws -> ScanResult {
        let cmd = "/usr/bin/du -k -d 1 " + Shell.shellQuote(path)
        let result = Shell.runAsAdmin(shellCommand: cmd)
        if result.exitCode == -128 { throw ScanError.cancelledAuthorization }
        return try parse(result: result, targetPath: path)
    }

    // MARK: - Parsing

    private static func parse(result: ShellResult, targetPath: String) throws -> ScanResult {
        // du prints partial output even on permission errors, so only bail when we
        // truly got nothing usable.
        if result.stdout.isEmpty && !result.succeeded {
            throw ScanError.failed(result.stderr.isEmpty ? "Scan failed." : result.stderr)
        }

        let fm = FileManager.default
        let normalizedTarget = URL(fileURLWithPath: targetPath).standardizedFileURL.path

        var target: DiskItem?
        var children: [DiskItem] = []

        for rawLine in result.stdout.split(separator: "\n") {
            // Format: "<kbytes>\t<path>"
            guard let tab = rawLine.firstIndex(of: "\t") else { continue }
            let kbString = rawLine[..<tab].trimmingCharacters(in: .whitespaces)
            let linePath = String(rawLine[rawLine.index(after: tab)...])
            guard let kb = Int64(kbString) else { continue }

            let url = URL(fileURLWithPath: linePath)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: linePath, isDirectory: &isDir)

            let item = DiskItem(url: url, byteSize: kb * 1024, isDirectory: isDir.boolValue)

            if url.standardizedFileURL.path == normalizedTarget {
                target = item
            } else {
                children.append(item)
            }
        }

        // Single-file target: du emits only the file's own line.
        let resolvedTarget = target ?? children.first ?? DiskItem(
            url: URL(fileURLWithPath: targetPath), byteSize: 0, isDirectory: false)
        let resolvedChildren = (target == nil) ? [] : children

        return ScanResult(
            target: resolvedTarget,
            children: resolvedChildren.sorted { $0.byteSize > $1.byteSize },
            partial: result.hasPermissionError && !result.stdout.isEmpty,
            stderr: result.stderr
        )
    }
}
