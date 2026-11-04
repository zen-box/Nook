import Foundation
import NookCore

/// Where an assistant conversation is kept between launches. `save(nil)` deletes it.
struct AgentHistoryStorage {
    let load: () -> Data?
    let save: (Data?) -> Void
}

/// The stored form of an assistant conversation: what the screen shows, the outcome of each
/// card, and the message history the model needs to continue. Images are not kept, and neither
/// are the records the assistant looked up; after a restart it searches again before changing
/// anything.
struct AgentHistorySnapshot: Codable {
    static let currentVersion = 1
    /// Conversation rows kept on disk, newest last.
    static let entryLimit = 300
    /// Messages sent back to the model as context.
    static let messageLimit = 80

    var version = Self.currentVersion
    var savedAt: Date
    var entries: [StoredEntry]
    var draftStates: [UUID: AgentDraftState]
    var draftNotes: [UUID: String]
    var answers: [UUID: String]
    var pendingPlanID: UUID?
    var openQuestionID: UUID?
    var undoPlan: AgentPlan?
    var undoablePlanID: UUID?
    var messages: [StoredMessage]

    struct StoredEntry: Codable {
        enum Kind: String, Codable {
            case user, assistant, question, draft, notice
        }

        var kind: Kind
        var text: String?
        var imageCount: Int?
        var isError: Bool?
        var questionID: UUID?
        var options: [String]?
        var plan: AgentPlan?
    }

    struct StoredCall: Codable {
        var id: String
        var name: String
        var arguments: JSONValue
        var providerPart: JSONValue?
    }

    struct StoredMessage: Codable {
        var role: String
        var text: String
        var imageCount: Int
        var calls: [StoredCall]
        var toolCallID: String?
        var toolName: String?
        var providerItems: [JSONValue]

        init(_ message: AIMessage) {
            role = message.role
            text = message.text
            imageCount = message.images.count
            calls = message.calls.map { StoredCall(id: $0.id, name: $0.name, arguments: $0.arguments, providerPart: $0.providerPart) }
            toolCallID = message.toolCallID
            toolName = message.toolName
            providerItems = message.providerItems
        }

        /// The message for the model. Images are gone, so the text says where one was.
        var message: AIMessage {
            var restored = text
            if imageCount > 0 {
                let note = "[\(imageCount) image(s) were attached here earlier and are no longer available.]"
                restored = restored.isEmpty ? note : restored + "\n" + note
            }
            return AIMessage(
                role: role,
                text: restored,
                calls: calls.map { AIToolCall(id: $0.id, name: $0.name, arguments: $0.arguments, providerPart: $0.providerPart) },
                toolCallID: toolCallID,
                toolName: toolName,
                providerItems: providerItems
            )
        }
    }

    /// The newest `limit` messages, starting at a user message so that no tool reply is kept
    /// without the call that asked for it.
    static func trimmed(_ messages: [AIMessage], limit: Int) -> [AIMessage] {
        guard messages.count > limit else { return messages }
        let start = messages.count - limit
        guard let cut = messages[start...].firstIndex(where: { $0.role == "user" }) else { return [] }
        return Array(messages[cut...])
    }
}
