import Foundation

/// Result of a full-subtree scan: the size of every directory beneath (and
/// including) the root, plus whether any entries were unreadable.
struct FullScanResult {
    let root: String                 // standardized
    let dirSizes: [String: Int64]
    let partial: Bool
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

/// Wraps `du -k <path>` (no `-d1`, so it reports every directory in the subtree).
/// `-k` gives numeric KB; the UI formats bytes to human units. One run indexes the
/// whole tree, which callers cache in a `ScanIndex` for instant browsing.
enum DiskScanner {

    static func standardize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Full scan as the current user.
    static func fullScan(path: String) throws -> FullScanResult {
        let result = Shell.run("/usr/bin/du", ["-k", path])
        return try parse(result: result, targetPath: path)
    }

    /// Full scan with administrator privileges (native auth prompt).
    static func fullScanAsAdmin(path: String) throws -> FullScanResult {
        let cmd = "/usr/bin/du -k " + Shell.shellQuote(path)
        let result = Shell.runAsAdmin(shellCommand: cmd)
        if result.exitCode == -128 { throw ScanError.cancelledAuthorization }
        return try parse(result: result, targetPath: path)
    }

    // MARK: - Parsing

    private static func parse(result: ShellResult, targetPath: String) throws -> FullScanResult {
        // du emits partial output even on permission errors, so only bail when we
        // truly got nothing usable.
        if result.stdout.isEmpty && !result.succeeded {
            throw ScanError.failed(result.stderr.isEmpty ? "Scan failed." : result.stderr)
        }

        var dirSizes: [String: Int64] = [:]
        for rawLine in result.stdout.split(separator: "\n") {
            // Format: "<kbytes>\t<path>"
            guard let tab = rawLine.firstIndex(of: "\t") else { continue }
            let kbString = rawLine[..<tab].trimmingCharacters(in: .whitespaces)
            let linePath = String(rawLine[rawLine.index(after: tab)...])
            guard let kb = Int64(kbString) else { continue }
            dirSizes[standardize(linePath)] = kb * 1024
        }

        return FullScanResult(
            root: standardize(targetPath),
            dirSizes: dirSizes,
            partial: result.hasPermissionError && !result.stdout.isEmpty,
            stderr: result.stderr
        )
    }
}
