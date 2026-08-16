import Foundation

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openAICompatible
    case localMLX

    var id: String { rawValue }
    var label: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAICompatible: return "OpenAI-compatible (OpenRouter…)"
        case .localMLX: return "Local (on-device)"
        }
    }
    /// Separate Keychain account per cloud provider so switching keeps both keys.
    var keychainAccount: String {
        switch self {
        case .anthropic: return "anthropic-api-key"
        case .openAICompatible: return "openai-api-key"
        case .localMLX: return "unused-local"
        }
    }
    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openAICompatible: return "https://openrouter.ai/api/v1"
        case .localMLX: return ""
        }
    }
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-5"
        case .openAICompatible: return "openai/gpt-4o-mini"
        case .localMLX: return LocalModelCatalog.defaultID
        }
    }
    var needsAPIKey: Bool { self != .localMLX }
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
    You are a macOS disk-cleanup advisor inside an app called Bytopolis. You are given a \
    JSON context scoped to ONLY the folder the user is CURRENTLY viewing — one level, not the \
    whole tree. It has: "currentPath" (the folder in view) and "currentSizeBytes"; and \
    "children" — its immediate entries only, each with name, sizeBytes, isDirectory, ageDays, \
    category, and a reclaim level (safe | caution | keep, or null if not classified). These \
    "children" are the ONLY items that exist for you; there is nothing nested beneath them in \
    this context. Reason strictly about "currentPath" and the entries in "children". Help the \
    user free space.

    Rules:
    - Use ONLY the entries in "children". Do NOT mention or invent any file/folder whose \
    "name" is not in that list, and never fabricate nested paths (e.g. "children/…", \
    "agno/lib") — you only have this one level. Do NOT invent the "reclaim"/"category" of an \
    item; if it's null, say it's unclassified.
    - Use ONLY the facts in the JSON (name, sizeBytes, ageDays, category, reclaim). Do \
    NOT invent descriptions of what a folder contains or which app/project it belongs to. \
    The "category" field already says what each item is (e.g. "npm packages", "Build \
    output") — use that; don't guess beyond it.
    - Only ever suggest deleting items with reclaim level "safe" or "caution". NEVER \
    suggest deleting user documents, photos, or anything marked "keep".
    - Prefer "safe" (regenerable caches/build output) first; flag "caution" items as \
    needing a check.
    - Be concise. When you recommend deletions, list the exact paths and a size in \
    human units (MB/GB), with a one-line reason from the category. Total up the space \
    that would be freed.
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
        // Local models are run by MLXRunner, not this HTTP client.
        guard config.provider != .localMLX else { throw LLMError.badResponse }
        guard let key = await Keychain.unlockedKey(account: config.provider.keychainAccount) else { throw LLMError.noAPIKey }

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
            request.setValue("Bytopolis", forHTTPHeaderField: "X-Title")          // OpenRouter attribution
            body = openAIBody(model: model, summaryJSON: summaryJSON, question: question)
        case .localMLX:
            throw LLMError.badResponse   // handled by MLXRunner, unreachable here
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

    // MARK: - Streaming (Server-Sent Events)

    /// Streams the answer token-by-token via `onToken`, so the chat shows text as it
    /// arrives instead of a spinner until the whole reply lands. Returns the full text.
    /// Falls back to a clear error if the endpoint rejects streaming.
    @discardableResult
    static func askStream(question: String, summaryJSON: String, config: LLMConfig,
                          onToken: @escaping (String) -> Void) async throws -> String {
        guard config.provider != .localMLX else { throw LLMError.badResponse }
        guard let key = await Keychain.unlockedKey(account: config.provider.keychainAccount) else { throw LLMError.noAPIKey }

        let base = config.baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let model = config.model.trimmingCharacters(in: .whitespaces)
        let path = config.provider == .anthropic ? "/messages" : "/chat/completions"
        guard let url = URL(string: base + path) else { throw LLMError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        var body: [String: Any]
        switch config.provider {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = anthropicBody(model: model, summaryJSON: summaryJSON, question: question)
        case .openAICompatible:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("Bytopolis", forHTTPHeaderField: "X-Title")
            body = openAIBody(model: model, summaryJSON: summaryJSON, question: question)
        case .localMLX:
            throw LLMError.badResponse
        }
        body["stream"] = true
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var errBody = ""
            for try await line in bytes.lines { errBody += line }
            throw LLMError.http(http.statusCode, errBody)
        }

        var full = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let piece = streamDelta(obj, provider: config.provider), !piece.isEmpty {
                full += piece
                onToken(piece)
            }
        }
        guard !full.isEmpty else { throw LLMError.badResponse }
        return full
    }

    /// Extracts the incremental text from one SSE JSON event for either API shape.
    private static func streamDelta(_ obj: [String: Any], provider: LLMProvider) -> String? {
        switch provider {
        case .anthropic:
            // {"type":"content_block_delta","delta":{"type":"text_delta","text":"…"}}
            if let delta = obj["delta"] as? [String: Any], let t = delta["text"] as? String { return t }
            return nil
        default:
            // {"choices":[{"delta":{"content":"…"}}]}
            if let choices = obj["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let t = delta["content"] as? String { return t }
            return nil
        }
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
