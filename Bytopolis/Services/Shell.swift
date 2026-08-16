import Foundation

/// Result of running a shell command.
struct ShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }
    /// `du` and friends exit non-zero and/or print this when a subpath can't be read.
    var hasPermissionError: Bool {
        exitCode != 0 || stderr.localizedCaseInsensitiveContains("permission denied")
    }
}

/// Runs external commands. Two modes:
///   - `run`: direct execution as the current user (fast path).
///   - `runAsAdmin`: escalates via `osascript ... with administrator privileges`,
///     which shows the native macOS auth dialog. No bundled `sudo`, no stored password.
enum Shell {

    /// Run an executable directly with explicit arguments (no shell interpolation,
    /// so paths with spaces/quotes are safe by construction).
    static func run(_ launchPath: String, _ arguments: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ShellResult(stdout: "", stderr: "Failed to launch \(launchPath): \(error.localizedDescription)", exitCode: -1)
        }

        // Drain stdout and stderr concurrently. Reading them sequentially can
        // deadlock: if one pipe's 64KB buffer fills while we're blocked reading
        // the other, the child blocks on write and never exits (e.g. `du`
        // flooding stderr with "Permission denied" on protected subtrees).
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "shell.pipe-read", attributes: .concurrent)
        queue.async(group: group) { outData = outPipe.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        group.wait()
        process.waitUntilExit()

        return ShellResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    /// Run a `/bin/sh -c` command string with administrator privileges via osascript.
    /// `shellCommand` must already be a valid POSIX shell command (callers build it
    /// with `shellQuote` on any path arguments).
    static func runAsAdmin(shellCommand: String) -> ShellResult {
        let script = "do shell script \(appleScriptString(shellCommand)) with administrator privileges"
        let result = run("/usr/bin/osascript", ["-e", script])

        // osascript surfaces a user cancel as error -128.
        if !result.succeeded && result.stderr.contains("-128") {
            return ShellResult(stdout: "", stderr: "Authorization cancelled.", exitCode: -128)
        }
        return result
    }

    // MARK: - Quoting

    /// Quote a string as a single POSIX shell word (single-quoted, with embedded
    /// single quotes escaped). Safe for arbitrary paths.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Encode a Swift string as an AppleScript string literal — escape backslashes
    /// then double quotes, and wrap in quotes.
    static func appleScriptString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}
