import Foundation

/// The swappable on-device inference backend. This stub compiles without the MLX Swift
/// packages; Feature C replaces this file's body with the MLX-backed implementation
/// (download via Hugging Face Hub + `MLXLMCommon.generate`).
enum MLXBackend {
    static var isAvailable: Bool { false }

    static func download(modelID: String,
                         onProgress: @Sendable @escaping (Double) -> Void) async throws {
        throw MLXError.notAvailable
    }

    static func generate(modelID: String,
                         system: String,
                         user: String,
                         onToken: @escaping (String) -> Void) async throws {
        throw MLXError.notAvailable
    }
}
