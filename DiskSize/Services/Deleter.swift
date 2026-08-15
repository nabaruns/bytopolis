import Foundation

enum DeleteError: Error, LocalizedError {
    case blockedTarget(String)
    case cancelledAuthorization
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .blockedTarget(let why): return why
        case .cancelledAuthorization: return "Authorization cancelled."
        case .failed(let msg): return msg
        }
    }
}

/// Permanent `rm -rf`. User path first; falls back to admin escalation on
/// permission errors. Includes a hard guardrail against catastrophic targets.
enum Deleter {

    /// Paths we refuse to `rm -rf` outright, regardless of confirmation.
    private static func guardTarget(_ path: String) throws {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let trimmed = normalized.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty || trimmed == "/" {
            throw DeleteError.blockedTarget("Refusing to delete the filesystem root.")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if trimmed == home {
            throw DeleteError.blockedTarget("Refusing to delete your home folder.")
        }
        // Block obvious top-level system dirs.
        let forbidden: Set<String> = ["/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/var", "/Applications", "/Users"]
        if forbidden.contains(trimmed) {
            throw DeleteError.blockedTarget("Refusing to delete a protected system location: \(trimmed)")
        }
    }

    /// Delete as the current user.
    static func remove(path: String) throws {
        try guardTarget(path)
        let result = Shell.run("/bin/rm", ["-rf", path])
        if !result.succeeded {
            throw DeleteError.failed(result.stderr.isEmpty ? "Delete failed." : result.stderr)
        }
    }

    /// Delete with administrator privileges (native auth prompt).
    static func removeAsAdmin(path: String) throws {
        try guardTarget(path)
        let cmd = "/bin/rm -rf " + Shell.shellQuote(path)
        let result = Shell.runAsAdmin(shellCommand: cmd)
        if result.exitCode == -128 { throw DeleteError.cancelledAuthorization }
        if !result.succeeded {
            throw DeleteError.failed(result.stderr.isEmpty ? "Delete failed." : result.stderr)
        }
    }
}
