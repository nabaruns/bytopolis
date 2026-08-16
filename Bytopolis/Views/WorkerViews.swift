import SwiftUI

/// Configure and launch a worker on a repo facility. Task + agent + mode, with an
/// explicit warning when the run is allowed to edit the repo.
struct WorkerConfigView: View {
    let repoName: String
    let repoPath: String
    var onStart: (AgentWorker.Agent, AgentWorker.Mode, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var available: [AgentWorker.Agent] = AgentWorker.Agent.allCases
    @State private var agent: AgentWorker.Agent = .claude
    @State private var mode: AgentWorker.Mode = .plan
    @State private var task = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Start a worker in \(repoName)", systemImage: "person.fill.badge.plus").font(.headline)
            Text(repoPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)

            if available.isEmpty {
                Label("No agent CLI found (claude / codex).", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout)
            } else {
                Picker("Agent", selection: $agent) {
                    ForEach(available) { Text($0.label).tag($0) }
                }
                Picker("Mode", selection: $mode) {
                    ForEach(AgentWorker.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text("Task").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $task)
                    .font(.body).frame(minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))

                if mode.isAuto {
                    Label("This lets the agent edit files in the repo. Changes are shown afterwards via git; review before committing.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(mode.isAuto ? "Start (can edit)" : "Start") {
                    onStart(agent, mode, task.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(available.isEmpty || task.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
        .task {
            let found = await Task.detached { AgentWorker.Agent.allCases.filter(AgentWorker.isAvailable) }.value
            available = found
            if let first = found.first, !found.contains(agent) { agent = first }
        }
    }
}

/// Live output of a running/finished worker.
struct WorkerPanel: View {
    @ObservedObject var worker: AgentWorker
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.badge.plus")
                VStack(alignment: .leading, spacing: 1) {
                    Text(worker.repoName).font(.headline)
                    Text("\(worker.agent.label) · \(worker.mode.rawValue)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            Text(worker.task).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if worker.transcript.isEmpty {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Starting…").foregroundStyle(.secondary) }
                        } else {
                            MarkdownText(text: worker.transcript).textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .onChange(of: worker.transcript) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            if let changes = worker.changesSummary {
                Label(changes, systemImage: "arrow.triangle.branch").font(.caption)
            }

            HStack {
                if worker.isRunning {
                    Button(role: .destructive) { worker.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(worker.transcript, forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(worker.transcript.isEmpty)
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worker.repoPath)])
                }
            }
        }
        .padding(12)
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .shadow(radius: 14)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch worker.status {
        case .running:
            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("running").font(.caption) }
        case .finished:
            Label("done", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .stopped:
            Label("stopped", systemImage: "stop.circle").font(.caption).foregroundStyle(.secondary)
        case .failed(let m):
            Label("failed", systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red).help(m)
        }
    }
}
