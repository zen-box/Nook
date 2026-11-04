import Foundation
import Testing
@testable import NookCore

struct NoteContentTests {
    @Test func legacyNotesKeepEveryFieldWhenOpenedAndSaved() throws {
        let old = Note(title: "旅行", body: "出发前\n确认航班", category: .travel,
                       checklist: [ChecklistItem(text: "带护照", isDone: true), ChecklistItem(text: "订酒店")],
                       attachments: [FileRef(name: "行程.jpg", kind: .image)],
                       createdAt: Date(timeIntervalSince1970: 1_793_721_600))
        let data = try NookJSON.makeEncoder().encode(old)
        #expect(!String(decoding: data, as: UTF8.self).contains("rich_content"))
        var decoded = try NookJSON.makeDecoder().decode(Note.self, from: data)
        #expect(decoded.content == nil)
        decoded.applyContent(decoded.editorRuns)
        #expect(decoded.body.hasPrefix(old.body))
        #expect(decoded.checklist == old.checklist)
        #expect(decoded.attachments == old.attachments)
        #expect(decoded.editorRuns.first?.text == old.body)
        #expect(try NookJSON.makeDecoder().decode(Note.self, from: NookJSON.makeEncoder().encode(decoded)) == decoded)
    }

    @Test func mixedContentPreservesOrderAndProjectsSearchAndTodos() {
        let item = ChecklistItem(text: "")
        let photo = FileRef(name: "照片.jpg", kind: .image)
        let runs = [NoteRun("准备\n", style: .heading, bold: true), NoteRun(checklist: item),
                    NoteRun("带", bold: true), NoteRun("护照📒\n", italic: true),
                    NoteRun(attachment: photo), NoteRun("\n回来后整理照片")]
        let note = Note(title: "旅行", category: .travel, content: runs)
        #expect(note.editorRuns == runs)
        #expect(note.body == "准备\n带护照📒\n\n回来后整理照片")
        #expect(note.checklist == [ChecklistItem(id: item.id, text: "带护照📒")])
        #expect(note.attachments == [photo])
        #expect(NoteQuery.filter([note], search: "护照").count == 1)
        #expect(NoteQuery.filter([note], search: "回来").count == 1)
    }

    @Test func checkboxStateStaysInSyncWithHomeActions() {
        let marker = ChecklistItem(text: "")
        var note = Note(title: "采购", category: .life, content: [NoteRun(checklist: marker), NoteRun("牛奶")])
        note.toggleChecklistItem(marker.id)
        #expect(note.checklist.first?.isDone == true)
        #expect(note.editorRuns.first?.checklist?.isDone == true)
        note.applyContent(note.editorRuns)
        #expect(note.checklist == [ChecklistItem(id: marker.id, text: "牛奶", isDone: true)])
    }

    @Test func removingMarkersUpdatesProjectionsAndDuplicatePhotosHaveOneFileRef() {
        let ref = FileRef(name: "photo.jpg", kind: .image)
        var note = Note(title: "", category: .personal,
                        content: [NoteRun(attachment: ref), NoteRun("\n"), NoteRun(attachment: ref)])
        #expect(note.attachments == [ref])
        #expect(!note.isBlank)
        note.applyContent([NoteRun("\n")])
        #expect(note.attachments.isEmpty)
        #expect(note.checklist.isEmpty)
        #expect(note.isBlank)
    }

    @Test func richContentAndFormatsSurviveBackupRoundTrip() throws {
        let runs = [NoteRun("标题\n", style: .heading, bold: true), NoteRun("普通文本"),
                    NoteRun(checklist: ChecklistItem(text: "", isDone: true)), NoteRun("完成", italic: true),
                    NoteRun(attachment: FileRef(name: "照片.jpg", kind: .image))]
        let note = Note(title: "文档", category: .work, content: runs,
                        createdAt: Date(timeIntervalSince1970: 1_793_721_600))
        let restored = try NookBackup.decode(NookBackup(notes: [note]).encoded())
        #expect(restored.notes == [note])
        #expect(restored.notes.first?.editorRuns == runs)
    }
}
