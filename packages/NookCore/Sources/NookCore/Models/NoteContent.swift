import Foundation

/// Text runs and one-character inline markers in a single editable document.
public struct NoteRun: Hashable, Codable, Sendable {
    public enum Style: String, Codable, Sendable { case body, heading }

    public var text: String
    public var style: Style
    public var bold: Bool
    public var italic: Bool
    public var checklist: ChecklistItem?
    public var attachment: FileRef?

    public init(_ text: String = "", style: Style = .body, bold: Bool = false,
                italic: Bool = false, checklist: ChecklistItem? = nil, attachment: FileRef? = nil) {
        self.text = text
        self.style = style
        self.bold = bold
        self.italic = italic
        self.checklist = checklist
        self.attachment = attachment
    }
}

extension Note {
    /// Preserve every legacy field when opening a note in the continuous editor.
    public var editorRuns: [NoteRun] {
        if let content { return content }
        var runs: [NoteRun] = []
        if !body.isEmpty { runs.append(NoteRun(body)) }
        if !checklist.isEmpty && !body.isEmpty && !body.hasSuffix("\n") { runs.append(NoteRun("\n")) }
        for item in checklist {
            runs.append(NoteRun(checklist: ChecklistItem(id: item.id, text: "", isDone: item.isDone)))
            runs.append(NoteRun(item.text + "\n"))
        }
        if !attachments.isEmpty, let last = runs.last, !last.text.hasSuffix("\n") {
            runs.append(NoteRun("\n"))
        }
        for ref in attachments {
            runs.append(NoteRun(attachment: ref))
            runs.append(NoteRun("\n"))
        }
        return runs
    }

    /// Keep existing search, home to-dos, cards and file cleanup on the same content.
    public mutating func applyContent(_ runs: [NoteRun]) {
        content = runs
        body = runs.filter { $0.checklist == nil && $0.attachment == nil }.map(\.text).joined()
        attachments = []
        checklist = []
        var pending: ChecklistItem?
        func finishItem() {
            if let pending { checklist.append(pending) }
            pending = nil
        }
        for run in runs {
            if let marker = run.checklist {
                finishItem()
                pending = ChecklistItem(id: marker.id, text: "", isDone: marker.isDone)
            } else if let ref = run.attachment {
                finishItem()
                if !attachments.contains(where: { $0.id == ref.id }) { attachments.append(ref) }
            } else if pending != nil {
                let parts = run.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                pending?.text += String(parts[0])
                if parts.count > 1 { finishItem() }
            }
        }
        finishItem()
    }

    public mutating func toggleChecklistItem(_ id: UUID) {
        guard let index = checklist.firstIndex(where: { $0.id == id }) else { return }
        checklist[index].isDone.toggle()
        if let content {
            var updated = content
            for i in updated.indices where updated[i].checklist?.id == id {
                updated[i].checklist?.isDone = checklist[index].isDone
            }
            self.content = updated
        }
    }
}
