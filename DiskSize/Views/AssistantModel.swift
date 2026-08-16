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

    // Persisted conversation history (resumable across launches).
    @Published var history: [ChatStore.Conversation] = []
    private var currentID = UUID()
    private var createdAt = Date()

    // Local-model download state
    @Published var downloading = false
    @Published var downloadProgress = 0.0
    @Published var downloadError: String?
    @Published var warming = false          // preloading the local model into memory
    private var warmedModel: String?

    // Provider config — persisted in UserDefaults (mirrored as @Published for the UI).
    @Published var provider: LLMProvider { didSet { d.set(provider.rawValue, forKey: "llmProvider") } }
    @Published var openaiBaseURL: String { didSet { d.set(openaiBaseURL, forKey: "openaiBaseURL") } }
    @Published var openaiModel: String { didSet { d.set(openaiModel, forKey: "openaiModel") } }
    @Published var anthropicModel: String { didSet { d.set(anthropicModel, forKey: "anthropicModel") } }
    @Published var localModelID: String { didSet { d.set(localModelID, forKey: "localModelID") } }

    weak var scan: ScanModel?

    private let d = UserDefaults.standard
    private var genTask: Task<Void, Never>?

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
        history = ChatStore.all()
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
        persist()   // save the user turn immediately, before the (possibly slow) reply

        let summary = scan?.assistantSummaryJSON() ?? "{}"
        let cfg = config

        genTask = Task {
            do {
                if cfg.provider == .localMLX {
                    try await MLXRunner.shared.generate(
                        summaryJSON: summary, question: q, modelID: cfg.model
                    ) { [weak self] token in
                        guard let self, self.messages.indices.contains(replyIndex) else { return }
                        self.messages[replyIndex].text += token
                    }
                } else {
                    try await LLMClient.askStream(
                        question: q, summaryJSON: summary, config: cfg
                    ) { [weak self] token in
                        guard let self, self.messages.indices.contains(replyIndex) else { return }
                        self.messages[replyIndex].text += token
                    }
                }
            } catch is CancellationError {
                // Keep whatever was streamed before the user stopped.
            } catch {
                if !Task.isCancelled { errorText = error.localizedDescription }
                // Drop the reply bubble only if nothing was produced.
                if messages.indices.contains(replyIndex), messages[replyIndex].text.isEmpty {
                    messages.remove(at: replyIndex)
                }
            }
            streaming = false
            persist()
        }
    }

    /// Preload the local model into memory (e.g. when the pane opens) so the first
    /// question isn't slow. No-op for cloud providers or a not-yet-downloaded model.
    func warmUpIfLocal() {
        guard provider == .localMLX, LocalModelStore.isDownloaded(localModelID),
              warmedModel != localModelID, !warming else { return }
        let id = localModelID
        warming = true
        Task {
            try? await MLXRunner.shared.warmUp(modelID: id)
            if provider == .localMLX { warmedModel = id }
            warming = false
        }
    }

    /// Stop an in-progress generation, keeping any partial text.
    func stop() {
        genTask?.cancel()
        streaming = false
    }

    // MARK: - Conversation history (persisted, resumable)

    /// Save the current transcript as a conversation, refreshing the history list.
    private func persist() {
        guard !messages.isEmpty else { return }
        let msgs = messages.map {
            ChatStore.Conversation.Message(
                role: $0.role == .user ? .user : .assistant, text: $0.text)
        }
        var convo = ChatStore.Conversation(
            id: currentID, createdAt: createdAt, updatedAt: Date(), messages: msgs)
        convo.title = ChatStore.Conversation.makeTitle(from: msgs)
        ChatStore.save(convo)
        history = ChatStore.all()
    }

    /// Start a fresh chat, saving the current one first.
    func newChat() {
        stop()
        persist()
        messages.removeAll()
        errorText = nil
        currentID = UUID()
        createdAt = Date()
    }

    /// Reopen a saved conversation, saving the current one first.
    func resume(_ convo: ChatStore.Conversation) {
        guard convo.id != currentID else { return }
        stop()
        persist()
        currentID = convo.id
        createdAt = convo.createdAt
        errorText = nil
        messages = convo.messages.map {
            Message(role: $0.role == .user ? .user : .assistant, text: $0.text)
        }
    }

    /// Delete a saved conversation; if it's the open one, start fresh.
    func deleteConversation(_ id: UUID) {
        ChatStore.delete(id)
        if id == currentID {
            messages.removeAll()
            errorText = nil
            currentID = UUID()
            createdAt = Date()
        }
        history = ChatStore.all()
    }

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
