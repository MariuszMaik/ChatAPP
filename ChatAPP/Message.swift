import Foundation

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

enum AttachmentType: String, Codable {
    case image
    case text
    case pdf
}

struct Attachment: Identifiable, Codable {
    var id: UUID = UUID()
    var type: AttachmentType
    var name: String
    var data: Data?
    var text: String?

    var displayName: String { name.isEmpty ? (type == .image ? "Image" : "File") : name }

    var icon: String {
        switch type {
        case .image: return "photo"
        case .pdf:   return "doc.fill"
        case .text:  return "doc.text.fill"
        }
    }
}

/// A single tool call requested by the assistant.
struct ToolCall: Identifiable, Codable {
    var id: String          // call_abc123
    var name: String        // e.g. "list_directory"
    var arguments: String   // raw JSON string, e.g. {"path": "."}
}

struct Message: Identifiable, Codable {
    var id: UUID = UUID()
    var role: MessageRole
    var content: String
    var attachments: [Attachment] = []
    var timestamp: Date = Date()
    var isStreaming: Bool = false

    /// Populated when role == .assistant and the model requested tool calls.
    var toolCalls: [ToolCall]?

    /// Populated when role == .tool — references which call this result belongs to.
    var toolCallId: String?

    /// Tool messages and tool-call assistant messages are not shown as regular bubbles.
    var isVisible: Bool {
        switch role {
        case .tool:                              return false   // hidden — only for API context
        case .assistant where toolCalls != nil:  return true   // shown as subtle chip row
        default:                                 return true
        }
    }
}
