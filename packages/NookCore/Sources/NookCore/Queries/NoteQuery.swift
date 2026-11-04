import Foundation

public enum NoteQuery {
    /// Notes in `category` (all when nil) that contain every word of `search` in their title,
    /// body, checklist or tags, ignoring case and accents. Sorted pinned first, then most
    /// recently edited.
    public static func filter(_ notes: [Note], search: String = "", category: NoteCategory? = nil) -> [Note] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        return notes
            .filter { note in
                (category == nil || note.category == category) && words.allSatisfy { contains(note, $0) }
            }
            .sorted(by: displayOrder)
    }

    /// Pinned notes first, then the most recently edited.
    public static func displayOrder(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func contains(_ note: Note, _ word: String) -> Bool {
        let fields = [note.title, note.body] + note.checklist.map(\.text) + note.tags
        return fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
