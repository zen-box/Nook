import Foundation

/// The fixed note groups shown as filter chips. Free-form folders replace them in P1 (spec §6.2 folder_id).
public enum NoteCategory: String, Codable, CaseIterable, Sendable {
    case work
    case travel
    case life
    case personal
}

public struct ChecklistItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var text: String
    public var isDone: Bool

    public init(id: UUID = UUIDv7.make(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case isDone = "done"
    }
}

public enum FileKind: String, Codable, Sendable {
    case image
    case pdf
    case document
    case other
}

/// A reference to an attachment. The bytes live in the file store, not in the record.
public struct FileRef: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: FileKind
    public var byteCount: Int64?

    public init(id: UUID = UUIDv7.make(), name: String, kind: FileKind, byteCount: Int64? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.byteCount = byteCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case byteCount = "size"
    }
}

public struct Note: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    /// Plain-text projection for search, previews and older clients.
    public var body: String
    /// Ordered text and inline markers. Nil means an older note, converted when first edited.
    public var content: [NoteRun]?
    public var category: NoteCategory
    public var tags: [String]
    public var isPinned: Bool
    public var checklist: [ChecklistItem]
    public var attachments: [FileRef]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUIDv7.make(),
        title: String,
        body: String = "",
        category: NoteCategory,
        tags: [String] = [],
        isPinned: Bool = false,
        checklist: [ChecklistItem] = [],
        attachments: [FileRef] = [],
        content: [NoteRun]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.tags = tags
        self.isPinned = isPinned
        self.checklist = checklist
        self.attachments = attachments
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        if let content { applyContent(content) }
    }

    public var completedChecklistCount: Int {
        checklist.filter(\.isDone).count
    }

    /// True when the note has no content worth keeping, e.g. a new note the user backed out of.
    public var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && checklist.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && attachments.isEmpty
    }

    /// The first non-empty body line without leading Markdown markers, for list rows.
    public var preview: String {
        for line in body.split(whereSeparator: \.isNewline) {
            var text = line.trimmingCharacters(in: .whitespaces)
            while let first = text.first, "#>-*+ ".contains(first) {
                text.removeFirst()
            }
            for marker in ["[ ] ", "[x] ", "[X] "] where text.hasPrefix(marker) {
                text.removeFirst(marker.count)
            }
            if !text.isEmpty {
                return text
            }
        }
        return ""
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case content = "rich_content"
        case category
        case tags
        case isPinned = "pinned"
        case checklist = "todos"
        case attachments = "file_refs"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
