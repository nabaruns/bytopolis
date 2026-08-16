import Foundation

/// A small instruct model available on Hugging Face (mlx-community) for on-device use.
struct LocalModel: Identifiable, Hashable {
    let id: String          // HF repo id, e.g. "mlx-community/Llama-3.2-3B-Instruct-4bit"
    let name: String
    let approxSize: String
}

enum LocalModelCatalog {
    static let models: [LocalModel] = [
        LocalModel(id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                   name: "Llama 3.2 · 3B Instruct (4-bit)", approxSize: "~1.8 GB"),
        LocalModel(id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
                   name: "Llama 3.2 · 1B Instruct (4-bit) — fastest", approxSize: "~0.7 GB"),
        LocalModel(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                   name: "Qwen2.5 · 1.5B Instruct (4-bit)", approxSize: "~1.0 GB")
    ]

    static let defaultID = "mlx-community/Llama-3.2-3B-Instruct-4bit"

    static func model(_ id: String) -> LocalModel? { models.first { $0.id == id } }
}

/// Tracks which local models have been downloaded (persisted in UserDefaults).
enum LocalModelStore {
    private static let key = "downloadedLocalModels"

    static func downloaded() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    static func isDownloaded(_ id: String) -> Bool { downloaded().contains(id) }
    static func markDownloaded(_ id: String) {
        var s = downloaded(); s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: key)
    }
    static func remove(_ id: String) {
        var s = downloaded(); s.remove(id)
        UserDefaults.standard.set(Array(s), forKey: key)
    }
}
