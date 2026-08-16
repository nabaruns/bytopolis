import SwiftUI

/// Owns the assistant conversation and provider configuration for the side pane.
/// Dispatches to `LLMClient` (cloud) or, once available, the on-device MLX runner.
@MainActor
final class AssistantModel: ObservableObject {

    struct Message: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
    }

    @Published var messages: [Message] = []
    @Published var input = ""
    @Published var streaming = false
    @Published var errorText: String?

    // Local-model download state
    @Published var downloading = false
    @Published var downloadProgress = 0.0
    @Published var downloadError: String?

    // Provider config — persisted in UserDefaults (mirrored as @Published for the UI).
    @Published var provider: LLMProvider { didSet { d.set(provider.rawValue, forKey: "llmProvider") } }
    @Published var openaiBaseURL: String { didSet { d.set(openaiBaseURL, forKey: "openaiBaseURL") } }
    @Published var openaiModel: String { didSet { d.set(openaiModel, forKey: "openaiModel") } }
    @Published var anthropicModel: String { didSet { d.set(anthropicModel, forKey: "anthropicModel") } }
    @Published var localModelID: String { didSet { d.set(localModelID, forKey: "localModelID") } }

    weak var scan: ScanModel?

    private let d = UserDefaults.standard

    let quickPrompts = [
        "What can I safely delete to free the most space?",
        "Free up 10 GB safely.",
        "Explain the biggest folders and whether they're safe to remove."
    ]

    init() {
        provider = LLMProvider(rawValue: d.string(forKey: "llmProvider") ?? "") ?? .anthropic
        openaiBaseURL = d.string(forKey: "openaiBaseURL") ?? LLMProvider.openAICompatible.defaultBaseURL
        openaiModel = d.string(forKey: "openaiModel") ?? LLMProvider.openAICompatible.defaultModel
        anthropicModel = d.string(forKey: "anthropicModel") ?? LLMProvider.anthropic.defaultModel
        localModelID = d.string(forKey: "localModelID") ?? LocalModelCatalog.defaultID
    }

    var config: LLMConfig {
        switch provider {
        case .anthropic:
            return LLMConfig(provider: .anthropic, baseURL: provider.defaultBaseURL, model: anthropicModel)
        case .openAICompatible:
            return LLMConfig(provider: .openAICompatible, baseURL: openaiBaseURL, model: openaiModel)
        case .localMLX:
            return LLMConfig(provider: .localMLX, baseURL: "", model: localModelID)
        }
    }

    /// True when the current provider is ready to answer (cloud needs a key; local needs a
    /// downloaded model).
    var isReady: Bool {
        switch provider {
        case .localMLX: return LocalModelStore.isDownloaded(localModelID)
        default: return Keychain.has(account: provider.keychainAccount)
        }
    }

    func send(_ raw: String? = nil) {
        let q = (raw ?? input).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !streaming else { return }
        input = ""
        errorText = nil
        messages.append(Message(role: .user, text: q))
        messages.append(Message(role: .assistant, text: ""))
        let replyIndex = messages.count - 1
        streaming = true

        let summary = scan?.assistantSummaryJSON() ?? "{}"
        let cfg = config

        Task {
            do {
                if cfg.provider == .localMLX {
                    try await MLXRunner.shared.generate(
                        summaryJSON: summary, question: q, modelID: cfg.model
                    ) { [weak self] token in
                        guard let self, self.messages.indices.contains(replyIndex) else { return }
                        self.messages[replyIndex].text += token
                    }
                } else {
                    let answer = try await LLMClient.ask(question: q, summaryJSON: summary, config: cfg)
                    if messages.indices.contains(replyIndex) { messages[replyIndex].text = answer }
                }
            } catch {
                errorText = error.localizedDescription
                if messages.indices.contains(replyIndex) { messages.remove(at: replyIndex) }
            }
            streaming = false
        }
    }

    func clear() { messages.removeAll(); errorText = nil }

    func downloadLocalModel() {
        guard !downloading else { return }
        downloading = true
        downloadProgress = 0
        downloadError = nil
        let id = localModelID
        Task {
            do {
                try await MLXRunner.shared.download(modelID: id) { p in
                    Task { @MainActor in self.downloadProgress = p }
                }
            } catch {
                downloadError = error.localizedDescription
            }
            downloading = false
            objectWillChange.send()   // refresh isDownloaded/isReady
        }
    }
}
