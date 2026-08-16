import Foundation

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openAICompatible

    var id: String { rawValue }
    var label: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAICompatible: return "OpenAI-compatible (OpenRouter…)"
        }
    }
    /// Separate Keychain account per provider so switching keeps both keys.
    var keychainAccount: String {
        switch self {
        case .anthropic: return "anthropic-api-key"
        case .openAICompatible: return "openai-api-key"
        }
    }
    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openAICompatible: return "https://openrouter.ai/api/v1"
        }
    }
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-5"
        case .openAICompatible: return "openai/gpt-4o-mini"
        }
    }
}

struct LLMConfig {
    var provider: LLMProvider
    var baseURL: String
    var model: String
}

enum LLMError: Error, LocalizedError {
    case noAPIKey
    case badURL
    case http(Int, String)
    case badResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key set for this provider."
        case .badURL: return "Invalid base URL."
        case .http(let code, let body): return "API error \(code): \(body)"
        case .badResponse: return "Unexpected response from the API."
        case .transport(let m): return m
        }
    }
}

/// Talks to either the Anthropic Messages API or any OpenAI-compatible
/// Chat Completions endpoint (OpenRouter, OpenAI, local gateways…). Advisory use:
/// it receives a metadata-only reclaim summary (no file contents) and returns text.
enum LLMClient {

    static let systemPrompt = """
    You are a macOS disk-cleanup advisor inside an app called DiskSize. You are given a \
    JSON summary of the largest reclaimable directories from a scan: each has a path, \
    size in bytes, age in days, a category, and a reclaim level (safe | caution | keep). \
    Help the user free space.

    Rules:
    - Only ever suggest deleting items with reclaim level "safe" or "caution". NEVER \
    suggest deleting user documents, photos, or anything marked "keep".
    - Prefer "safe" (regenerable caches/build output) first; flag "caution" items as \
    needing a check.
    - Be concise. When you recommend deletions, list the exact paths and their sizes, \
    and give a one-line reason. Total up the space that would be freed.
    - You cannot delete anything yourself — the user selects and confirms in the app. \
    Never claim you deleted something.
    """

    private static func userText(summaryJSON: String, question: String) -> String {
        """
        Reclaimable scan summary (JSON):
        \(summaryJSON)

        Question: \(question)
        """
    }

    // MARK: - Request bodies (exposed for testing)

    static func anthropicBody(model: String, summaryJSON: String, question: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userText(summaryJSON: summaryJSON, question: question)]]
        ]
    }

    static func openAIBody(model: String, summaryJSON: String, question: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText(summaryJSON: summaryJSON, question: question)]
            ]
        ]
    }

    // MARK: - Networking

    static func ask(question: String, summaryJSON: String, config: LLMConfig) async throws -> String {
        guard let key = Keychain.get(account: config.provider.keychainAccount) else { throw LLMError.noAPIKey }

        let base = config.baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let model = config.model.trimmingCharacters(in: .whitespaces)

        let path = config.provider == .anthropic ? "/messages" : "/chat/completions"
        guard let url = URL(string: base + path) else { throw LLMError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        switch config.provider {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = anthropicBody(model: model, summaryJSON: summaryJSON, question: question)
        case .openAICompatible:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("DiskSize", forHTTPHeaderField: "X-Title")          // OpenRouter attribution
            body = openAIBody(model: model, summaryJSON: summaryJSON, question: question)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }

        let text = config.provider == .anthropic
            ? parseAnthropic(data) : parseOpenAI(data)
        guard let text, !text.isEmpty else { throw LLMError.badResponse }
        return text
    }

    // MARK: - Response parsing (exposed for testing)

    static func parseAnthropic(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else { return nil }
        return content.compactMap { $0["text"] as? String }.joined()
    }

    static func parseOpenAI(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }
}
