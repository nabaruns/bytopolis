import Foundation

enum ClaudeError: Error, LocalizedError {
    case noAPIKey
    case http(Int, String)
    case badResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Anthropic API key set."
        case .http(let code, let body): return "API error \(code): \(body)"
        case .badResponse: return "Unexpected response from the API."
        case .transport(let m): return m
        }
    }
}

/// Thin client for the Anthropic Messages API. Advisory use only: it receives a
/// compact, metadata-only summary of reclaimable items (paths, sizes, ages,
/// categories — never file contents) and returns a natural-language answer.
enum ClaudeClient {

    static let defaultModel = "claude-sonnet-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private static let systemPrompt = """
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

    /// Build the request body (exposed for testing without a network call).
    static func requestBody(model: String, summaryJSON: String, question: String) -> [String: Any] {
        let userText = """
        Reclaimable scan summary (JSON):
        \(summaryJSON)

        Question: \(question)
        """
        return [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userText]
            ]
        ]
    }

    /// Ask Claude a question grounded in the scan summary. Returns the answer text.
    static func ask(question: String, summaryJSON: String, model: String = defaultModel) async throws -> String {
        guard let key = Keychain.apiKey() else { throw ClaudeError.noAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(model: model, summaryJSON: summaryJSON, question: question))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }

        // Response: { "content": [ { "type": "text", "text": "..." }, ... ] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw ClaudeError.badResponse
        }
        let text = content.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? "(no answer)" : text
    }
}
