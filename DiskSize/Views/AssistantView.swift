import SwiftUI

/// Advisory cleanup assistant. Sends a metadata-only summary of reclaimable items
/// (paths, sizes, ages, categories — never file contents) to Claude and shows the
/// answer. It never deletes anything; the user acts via the Reclaim sheet.
struct AssistantView: View {
    @ObservedObject var model: ScanModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("assistantModel") private var modelName = ClaudeClient.defaultModel
    @State private var hasKey = Keychain.hasAPIKey
    @State private var keyField = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var loading = false
    @State private var errorText: String?

    private let quickPrompts = [
        "What can I safely delete to free the most space?",
        "Free up 10 GB safely.",
        "Explain the biggest folders and whether they're safe to remove."
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if hasKey { conversation } else { keyEntry }
            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Reclaim Assistant", systemImage: "wand.and.stars").font(.title3.bold())
                Spacer()
                if hasKey {
                    Button("Change key") { hasKey = false; keyField = "" }
                        .buttonStyle(.link).font(.caption)
                }
            }
            Text("Sends folder paths, sizes, ages, and categories (never file contents) to Anthropic. Advisory only — it never deletes anything.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your Anthropic API key").font(.headline)
            Text("Stored in your macOS Keychain. Get one at console.anthropic.com.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("sk-ant-…", text: $keyField)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Save Key") {
                    Keychain.setAPIKey(keyField)
                    hasKey = Keychain.hasAPIKey
                    keyField = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding(12)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick questions").font(.caption).foregroundStyle(.secondary)
            ForEach(quickPrompts, id: \.self) { p in
                Button {
                    question = p
                    send()
                } label: {
                    Text(p).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(loading)
            }

            HStack {
                TextField("Ask about what to clean up…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Ask") { send() }
                    .disabled(loading || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            ScrollView {
                if loading {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let errorText {
                    Text(errorText).foregroundStyle(.red).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if answer.isEmpty {
                    Text("Ask a question to get grounded, path-specific advice from your scan.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(answer).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Model").font(.caption).foregroundStyle(.secondary)
            TextField("model", text: $modelName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Spacer()
            Button("Open Reclaim…") { model.showAssistant = false; model.showReclaim = true; model.loadReclaim() }
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private func send() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loading = true
        errorText = nil
        answer = ""
        let summary = model.assistantSummaryJSON() ?? "{}"
        let chosenModel = modelName.trimmingCharacters(in: .whitespaces).isEmpty ? ClaudeClient.defaultModel : modelName
        Task {
            do {
                answer = try await ClaudeClient.ask(question: q, summaryJSON: summary, model: chosenModel)
            } catch {
                errorText = error.localizedDescription
            }
            loading = false
        }
    }
}
