import SwiftUI

/// Advisory cleanup assistant. Sends a metadata-only summary of reclaimable items
/// (paths, sizes, ages, categories — never file contents) to the configured LLM and
/// shows the answer. Supports Anthropic and any OpenAI-compatible endpoint
/// (OpenRouter, OpenAI, local gateways). It never deletes anything.
struct AssistantView: View {
    @ObservedObject var model: ScanModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("llmProvider") private var providerRaw = LLMProvider.anthropic.rawValue
    @AppStorage("anthropicModel") private var anthropicModel = LLMProvider.anthropic.defaultModel
    @AppStorage("openaiBaseURL") private var openaiBaseURL = LLMProvider.openAICompatible.defaultBaseURL
    @AppStorage("openaiModel") private var openaiModel = LLMProvider.openAICompatible.defaultModel

    @State private var hasKey = false
    @State private var keyField = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var loading = false
    @State private var errorText: String?

    private var provider: LLMProvider { LLMProvider(rawValue: providerRaw) ?? .anthropic }

    private var config: LLMConfig {
        switch provider {
        case .anthropic:
            return LLMConfig(provider: .anthropic, baseURL: provider.defaultBaseURL, model: anthropicModel)
        case .openAICompatible:
            return LLMConfig(provider: .openAICompatible, baseURL: openaiBaseURL, model: openaiModel)
        }
    }

    private let quickPrompts = [
        "What can I safely delete to free the most space?",
        "Free up 10 GB safely.",
        "Explain the biggest folders and whether they're safe to remove."
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            settings
            Divider()
            if hasKey { conversation } else { keyEntry }
            Divider()
            footer
        }
        .onAppear { hasKey = Keychain.has(account: provider.keychainAccount) }
        .onChange(of: providerRaw) { hasKey = Keychain.has(account: provider.keychainAccount); keyField = "" }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Reclaim Assistant", systemImage: "wand.and.stars").font(.title3.bold())
            Text("Sends folder paths, sizes, ages, and categories (never file contents) to your chosen provider. Advisory only — it never deletes anything.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Provider", selection: $providerRaw) {
                ForEach(LLMProvider.allCases) { Text($0.label).tag($0.rawValue) }
            }
            if provider == .openAICompatible {
                HStack {
                    Text("Base URL").frame(width: 70, alignment: .leading).foregroundStyle(.secondary)
                    TextField("https://openrouter.ai/api/v1", text: $openaiBaseURL)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                }
                HStack {
                    Text("Model").frame(width: 70, alignment: .leading).foregroundStyle(.secondary)
                    TextField("openai/gpt-4o-mini", text: $openaiModel)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                }
            } else {
                HStack {
                    Text("Model").frame(width: 70, alignment: .leading).foregroundStyle(.secondary)
                    TextField("claude-sonnet-5", text: $anthropicModel)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                }
            }
        }
        .padding(12)
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your \(provider == .anthropic ? "Anthropic" : "provider") API key").font(.headline)
            Text(provider == .anthropic
                 ? "Stored in your macOS Keychain. Get one at console.anthropic.com."
                 : "Stored in your macOS Keychain. For OpenRouter, get a key at openrouter.ai/keys.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField(provider == .anthropic ? "sk-ant-…" : "sk-or-… / sk-…", text: $keyField)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Save Key") {
                    Keychain.set(keyField, account: provider.keychainAccount)
                    hasKey = Keychain.has(account: provider.keychainAccount)
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
            if hasKey {
                Button("Change key") { Keychain.delete(account: provider.keychainAccount); hasKey = false; keyField = "" }
                    .buttonStyle(.link).font(.caption)
            }
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
        let cfg = config
        Task {
            do {
                answer = try await LLMClient.ask(question: q, summaryJSON: summary, config: cfg)
            } catch {
                errorText = error.localizedDescription
            }
            loading = false
        }
    }
}
