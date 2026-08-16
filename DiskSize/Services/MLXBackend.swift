import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// On-device inference backed by Apple MLX (mlx-swift-examples 2.29.x). Downloads an
/// instruct model from Hugging Face and generates text fully offline. Loaded model
/// containers are cached so repeat questions don't reload weights.
enum MLXBackend {
    static var isAvailable: Bool { true }

    private static let cache = NSCache<NSString, ModelContainer>()

    static func download(modelID: String,
                         onProgress: @Sendable @escaping (Double) -> Void) async throws {
        _ = try await container(for: modelID, onProgress: onProgress)
    }

    static func generate(modelID: String,
                         system: String,
                         user: String,
                         onToken: @escaping (String) -> Void) async throws {
        let modelContainer = try await container(for: modelID, onProgress: { _ in })

        let chat: [Chat.Message] = [
            Chat.Message(role: .system, content: system),
            Chat.Message(role: .user, content: user)
        ]
        let userInput = UserInput(chat: chat)

        let stream: AsyncStream<Generation> = try await modelContainer.perform { context in
            let lmInput = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(temperature: 0.6)
            return try MLXLMCommon.generate(input: lmInput, parameters: parameters, context: context)
        }

        for await generation in stream {
            if Task.isCancelled { break }
            if let text = generation.chunk {
                await MainActor.run { onToken(text) }
            }
        }
    }

    private static func container(for id: String,
                                  onProgress: @Sendable @escaping (Double) -> Void) async throws -> ModelContainer {
        // Bound GPU cache to avoid runaway memory on smaller Macs.
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

        if let cached = cache.object(forKey: id as NSString) { return cached }
        let configuration = ModelConfiguration(id: id)
        let loaded = try await LLMModelFactory.shared.loadContainer(
            hub: defaultHubApi, configuration: configuration
        ) { progress in
            onProgress(progress.fractionCompleted)
        }
        cache.setObject(loaded, forKey: id as NSString)
        return loaded
    }
}
