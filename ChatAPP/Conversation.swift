import Foundation

struct Conversation: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var messages: [Message] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    static func generateTitle(from messages: [Message]) -> String {
        guard let first = messages.first(where: { $0.role == .user && !$0.content.isEmpty }) else {
            return "New Conversation"
        }
        let text = first.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 60 ? String(text.prefix(60)) + "…" : text
    }
}
