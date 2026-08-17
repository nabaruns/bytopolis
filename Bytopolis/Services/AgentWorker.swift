import Foundation

/// A headless coding-agent run inside a repo facility. Spawns `claude -p` (stream-json)
/// or `codex exec` in the repo directory, streams output into `transcript`, and reports
/// the resulting git changes. Never starts on its own — always user-initiated + gated.
@MainActor
final class AgentWorker: ObservableObject, Identifiable {

    enum Agent: String, CaseIterable, Identifiable {
        case claude, codex
        var id: String { rawValue }
        var label: String { self == .claude ? "Claude Code" : "Codex" }
        var binary: String { rawValue }
    }
    enum Mode: String, CaseIterable, Identifiable {
        case plan = "Plan (read-only)"
        case auto = "Allow edits"
        var id: String { rawValue }
        var isAuto: Bool { self == .auto }
    }
    enum Status: Equatable { case running, finished, failed(String), stopped }

    /// A coarse visual state for the city avatar. "waiting" = running but the agent has been
    /// silent for a beat (thinking / waiting on the model or a tool), vs "working" = actively
    /// streaming output.
    enum Phase { case working, waiting, done, failed, stopped }

    var phase: Phase {
        switch status {
        case .running: return Date().timeIntervalSince(lastOutputAt) < 3 ? .working : .waiting
        case .finished: return .done
        case .failed:   return .failed
        case .stopped:  return .stopped
        }
    }

    let id = UUID()
    let repoPath: String
    let repoName: String
    let agent: Agent
    let mode: Mode
    let task: String

    @Published var transcript = ""
    @Published var status: Status = .running
    @Published var changesSummary: String?
    /// When the agent last produced output — drives the working/waiting distinction.
    @Published var lastOutputAt = Date()

    /// Called on the main actor whenever the run ends (finished/failed/stopped).
    var onEnd: (() -> Void)?

    private var process: Process?
    private var outPipe: Pipe?
    private var errPipe: Pipe?
    private var lineBuffer = Data()

    init(repoPath: String, agent: Agent, mode: Mode, task: String) {
        self.repoPath = repoPath
        self.repoName = (repoPath as NSString).lastPathComponent
        self.agent = agent
        self.mode = mode
        self.task = task
    }

    var isRunning: Bool { status == .running }

    func start() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")     // login shell → PATH resolves claude/codex
        proc.arguments = ["-lc", Self.command(agent: agent, mode: mode, task: task)]
        proc.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = FileHandle.nullDevice
        outPipe = out; errPipe = err

        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            Task { @MainActor in self?.ingest(d) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            let s = String(decoding: d, as: UTF8.self)
            Task { @MainActor in self?.lastOutputAt = Date(); self?.transcript += s }
        }
        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in self?.finish(code: p.terminationStatus) }
        }

        do { try proc.run(); process = proc }
        catch { status = .failed(error.localizedDescription); onEnd?() }
    }

    func stop() {
        guard isRunning else { return }
        process?.terminate()
        status = .stopped
        cleanup()
        onEnd?()
    }

    // MARK: - Streaming

    private func ingest(_ data: Data) {
        lastOutputAt = Date()
        if agent == .claude {
            // stream-json: one JSON object per line.
            lineBuffer.append(data)
            while let nl = lineBuffer.firstIndex(of: 0x0A) {
                let lineData = lineBuffer[lineBuffer.startIndex..<nl]
                lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8) { appendClaudeLine(line) }
            }
        } else {
            transcript += String(decoding: data, as: UTF8.self)
        }
    }

    private func appendClaudeLine(_ line: String) {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(t.utf8)) as? [String: Any] else {
            transcript += t + "\n"; return
        }
        switch obj["type"] as? String {
        case "assistant":
            if let msg = obj["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] {
                for c in content {
                    if let text = c["text"] as? String {
                        transcript += text
                    } else if c["type"] as? String == "tool_use", let name = c["name"] as? String {
                        transcript += "\n_⚙ \(name)_\n"
                    }
                }
            }
        case "result":
            if let r = obj["result"] as? String, !r.isEmpty {
                if !transcript.hasSuffix(r) { transcript += "\n\n" + r }
            }
        default:
            break
        }
    }

    private func finish(code: Int32) {
        cleanup()
        if isRunning { status = code == 0 ? .finished : .failed("exited with code \(code)") }
        changesSummary = Self.gitChanges(repoPath)
        onEnd?()
    }

    private func cleanup() {
        outPipe?.fileHandleForReading.readabilityHandler = nil
        errPipe?.fileHandleForReading.readabilityHandler = nil
    }

    // MARK: - Commands

    nonisolated static func command(agent: Agent, mode: Mode, task: String) -> String {
        let q = Shell.shellQuote(task)
        switch agent {
        case .claude:
            var c = "claude -p \(q) --output-format stream-json --verbose"
            if mode.isAuto { c += " --dangerously-skip-permissions" }
            return c
        case .codex:
            return mode.isAuto
                ? "codex exec --full-auto \(q)"
                : "codex exec --sandbox read-only \(q)"
        }
    }

    /// Summarize what the run changed on disk.
    nonisolated static func gitChanges(_ repo: String) -> String? {
        let status = Shell.run("/usr/bin/git", ["-C", repo, "status", "--porcelain"])
        guard status.succeeded else { return nil }
        let changed = status.stdout.split(separator: "\n").count
        if changed == 0 { return "No file changes." }
        let shortstat = Shell.run("/usr/bin/git", ["-C", repo, "diff", "--shortstat"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(changed) file\(changed == 1 ? "" : "s") changed" + (shortstat.isEmpty ? "" : " · \(shortstat)")
    }

    /// Whether the agent binary actually runs on this machine (guards a dangling symlink).
    nonisolated static func isAvailable(_ agent: Agent) -> Bool {
        Shell.run("/bin/zsh", ["-lc", "\(agent.binary) --version"]).succeeded
    }
}

/// Tracks all active/finished workers (one or more per repo).
@MainActor
final class WorkerStore: ObservableObject {
    @Published private(set) var workers: [AgentWorker] = []

    @discardableResult
    func start(repoPath: String, agent: AgentWorker.Agent,
               mode: AgentWorker.Mode, task: String) -> AgentWorker {
        let worker = AgentWorker(repoPath: repoPath, agent: agent, mode: mode, task: task)
        workers.append(worker)
        worker.start()
        return worker
    }

    func running(forRepo path: String) -> Bool {
        workers.contains { $0.repoPath == path && $0.isRunning }
    }

    func remove(_ worker: AgentWorker) {
        worker.stop()
        workers.removeAll { $0.id == worker.id }
    }
}
