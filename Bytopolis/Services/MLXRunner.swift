import Foundation

enum MLXError: Error, LocalizedError {
    case notAvailable
    case downloadFailed(String)
    case generateFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "On-device model support isn't built into this copy of Bytopolis yet."
        case .downloadFailed(let m): return "Model download failed: \(m)"
        case .generateFailed(let m): return "On-device generation failed: \(m)"
        }
    }
}

/// Runs a local MLX model. This is the scaffold; the MLX-backed implementation is added
/// when the MLX Swift packages are linked (Feature C). Until then, calls throw
/// `MLXError.notAvailable` so the rest of the app compiles and runs.
///
/// The shared system prompt is reused from `LLMClient.systemPrompt`.
@MainActor
final class MLXRunner {
    static let shared = MLXRunner()
    private init() {}

    /// Whether on-device inference is compiled in (false until MLX is linked).
    var isAvailable: Bool { MLXBackend.isAvailable }

    /// Download a model from Hugging Face, reporting fractional progress (0…1).
    func download(modelID: String, onProgress: @Sendable @escaping (Double) -> Void) async throws {
        try await MLXBackend.download(modelID: modelID, onProgress: onProgress)
        LocalModelStore.markDownloaded(modelID)
    }

    /// Preload the model into memory so the first generation isn't slow.
    func warmUp(modelID: String) async throws {
        try await MLXBackend.warmUp(modelID: modelID)
    }

    /// Generate an answer, streaming tokens via `onToken` (called on the main actor).
    func generate(summaryJSON: String,
                  question: String,
                  modelID: String,
                  onToken: @escaping (String) -> Void) async throws {
        let system = LLMClient.systemPrompt
        // Small on-device models drift, so we repeat the hard constraint right next to the
        // data: only ever name paths/files that literally appear in the JSON below.
        let user = """
        Here is the JSON context for the folder the user is viewing. Every path and file name \
        you mention MUST appear verbatim in this JSON — do NOT invent file names.

        \(summaryJSON)

        Question: \(question)

        Answer using only the entries above. Give exact names/paths and sizes, and don't \
        make up files that aren't listed.
        """
        try await MLXBackend.generate(modelID: modelID, system: system, user: user, onToken: onToken)
    }
}
