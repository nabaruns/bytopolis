import Foundation

/// On-disk persistence for assistant conversations. Each conversation is one JSON file in
/// `~/Library/Application Support/DiskSize/Conversations/`, so history survives relaunches
/// and any single chat can be resumed. Conversations are small (plain text), so listing
/// reads them all and sorts by recency.
enum ChatStore {

    /// A saved conversation: its messages plus metadata for the history picker.
    struct Conversation: Codable, Identifiable {
        enum Role: String, Codable { case user, assistant }
        struct Message: Codable, Identifiable {
            var id = UUID()
            var role: Role
            var text: String
        }

        let id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var messages: [Message]

        init(id: UUID = UUID(), title: String = "New chat",
             createdAt: Date = Date(), updatedAt: Date = Date(), messages: [Message] = []) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.messages = messages
        }

        /// A short title derived from the first user message.
        static func makeTitle(from messages: [Message]) -> String {
            guard let first = messages.first(where: { $0.role == .user })?.text
                    .trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else {
                return "New chat"
            }
            let oneLine = first.replacingOccurrences(of: "\n", with: " ")
            return oneLine.count > 60 ? String(oneLine.prefix(60)) + "…" : oneLine
        }
    }

    private static let fm = FileManager.default

    private static var dir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiskSize/Conversations", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func fileURL(_ id: UUID) -> URL {
        dir.appendingPathComponent("\(id.uuidString).json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func save(_ convo: Conversation) {
        guard let data = try? encoder.encode(convo) else { return }
        try? data.write(to: fileURL(convo.id), options: .atomic)
    }

    static func delete(_ id: UUID) {
        try? fm.removeItem(at: fileURL(id))
    }

    /// All saved conversations, most-recently-updated first. Skips empty ones.
    static func all() -> [Conversation] {
        guard let names = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return names
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Conversation.self, from: Data(contentsOf: $0)) }
            .filter { !$0.messages.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
