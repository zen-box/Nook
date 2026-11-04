import Foundation

/// A dated task is separate from a note's undated checklist.
public struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var dueAt: Date?
    public var reminderMinutes: Int?
    public var isCompleted: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUIDv7.make(), title: String, notes: String = "", dueAt: Date? = nil,
                reminderMinutes: Int? = nil, isCompleted: Bool = false, createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id; self.title = title; self.notes = notes; self.dueAt = dueAt
        self.reminderMinutes = reminderMinutes; self.isCompleted = isCompleted
        self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
    }
}
