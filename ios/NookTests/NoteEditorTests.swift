import Foundation
import GRDB
import NookCore
import Testing
import UIKit
@testable import Nook

@MainActor
struct NoteEditorTests {
    @Test func checklistReturnContinuesAndAnEmptyItemExits() throws {
        let files = AttachmentStore.makeTemporary()
        defer { try? FileManager.default.removeItem(at: files.folder) }
        let view = NoteInputView(usingTextLayoutManager: false)
        let session = NoteEditorSession()
        session.attach(view, attachments: files)
        session.setSource([NoteRun(checklist: ChecklistItem(text: "")), NoteRun("带护照")])
        view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
        #expect(!session.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: "\n"))
        var note = Note(title: "", category: .personal, content: session.lastRuns)
        #expect(note.checklist.map(\.text) == ["带护照", ""])
        #expect(!session.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: "\n"))
        note.applyContent(session.lastRuns)
        #expect(note.checklist.map(\.text) == ["带护照"])
        #expect(view.text == "\u{FFFC}带护照\n")
    }

    @Test func toolbarChecklistInsertionCanBeUndoneAndRedone() throws {
        let files = AttachmentStore.makeTemporary()
        defer { try? FileManager.default.removeItem(at: files.folder) }
        let view = NoteInputView(usingTextLayoutManager: false)
        let session = NoteEditorSession()
        session.attach(view, attachments: files)
        session.setSource([NoteRun("中文🙂")])
        view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
        let undo = try #require(view.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        session.toggleChecklist()
        undo.endUndoGrouping()
        let edited = session.lastRuns
        #expect(edited.first?.checklist != nil)
        session.undo()
        #expect(session.lastRuns == [NoteRun("中文🙂")])
        session.redo()
        #expect(session.lastRuns == edited)
    }

    @Test func nativeDocumentRoundTripsTextFormatsChecklistAndPhotoOrder() throws {
        let files = AttachmentStore.makeTemporary()
        defer { try? FileManager.default.removeItem(at: files.folder) }
        let photo = FileRef(name: "photo.jpg", kind: .image)
        let item = ChecklistItem(text: "", isDone: true)
        let runs = [NoteRun("标题\n", style: .heading, bold: true), NoteRun("中文🙂\n", italic: true),
                    NoteRun(checklist: item), NoteRun("带护照\n"), NoteRun(attachment: photo), NoteRun("\n结尾", bold: true)]
        let text = NoteTextCodec.attributed(runs, attachments: files)
        #expect(NoteTextCodec.runs(text) == runs)
        #expect(text.string == "标题\n中文🙂\n\u{FFFC}带护照\n\u{FFFC}\n结尾")
    }

    @Test func richDocumentPersistsAndHomeToggleChangesTheInlineCheckbox() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "note-reopen-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "test.sqlite").path
        let writer = try DatabaseQueue(path: path)
        let database = try AppDatabase(writer)
        let item = ChecklistItem(text: "")
        let note = Note(title: "清单", category: .travel,
                        content: [NoteRun("行前准备\n", bold: true), NoteRun(checklist: item), NoteRun("护照")],
                        createdAt: Date(timeIntervalSince1970: 1_793_721_600))
        try database.save(note)
        try writer.close()
        let reopenedWriter = try DatabaseQueue(path: path)
        defer { try? reopenedWriter.close() }
        let reopened = try AppDatabase(reopenedWriter)
        #expect(try reopened.loadSnapshot().notes == [note])
        let store = AppStore(database: reopened, attachments: .makeTemporary(),
                             defaults: UserDefaults(suiteName: "nook.tests.\(UUID())")!, vaultParameters: .testing)
        store.toggleChecklistItem(item.id, in: note.id)
        #expect(store.note(id: note.id)?.content?[1].checklist?.isDone == true)
        #expect(try reopened.loadSnapshot().notes.first?.content?[1].checklist?.isDone == true)
    }

    @Test func upgradingAnExistingDatabasePreservesTheLegacyNote() throws {
        let writer = try DatabaseQueue()
        try AppDatabase.migrator.migrate(writer, upTo: "v2-vault-argon2id")
        let old = Note(title: "原有便签", body: "正文", category: .personal)
        try writer.write { db in
            try db.execute(sql: "INSERT INTO note (id,title,body,category,tags,pinned,todos,file_refs,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
                           arguments: [old.id, old.title, old.body, old.category.rawValue, "[]", false, "[]", "[]", old.createdAt, old.updatedAt])
        }
        let upgraded = try AppDatabase(writer)
        let loaded = try #require(try upgraded.loadSnapshot().notes.first)
        #expect(loaded.title == old.title)
        #expect(loaded.body == old.body)
        #expect(loaded.content == nil)
        var edited = loaded
        edited.applyContent(edited.editorRuns)
        try upgraded.save(edited)
        #expect(try upgraded.loadSnapshot().notes.first?.content == [NoteRun("正文")])
    }

    @Test func removingAPhotoKeepsItsBytesForUndoUntilEditorCloses() throws {
        let files = AttachmentStore.makeTemporary()
        defer { try? FileManager.default.removeItem(at: files.folder) }
        let database = try AppDatabase.makeInMemory()
        let store = AppStore(database: database, attachments: files,
                             defaults: UserDefaults(suiteName: "nook.tests.\(UUID())")!, vaultParameters: .testing)
        let ref = FileRef(name: "photo.jpg", kind: .image)
        try Data([1, 2, 3]).write(to: files.imageURL(for: ref))
        var note = Note(title: "照片", category: .personal, content: [NoteRun(attachment: ref)])
        #expect(store.saveNote(note))
        note.applyContent([])
        #expect(store.saveNote(note, retainingAttachments: [ref]))
        #expect(FileManager.default.fileExists(atPath: files.imageURL(for: ref).path))
        note.applyContent([NoteRun(attachment: ref)])
        #expect(store.saveNote(note, retainingAttachments: [ref]))
        store.discardUnreferencedPhotos([ref])
        #expect(FileManager.default.fileExists(atPath: files.imageURL(for: ref).path))
        note.applyContent([])
        #expect(store.saveNote(note, retainingAttachments: [ref]))
        store.discardUnreferencedPhotos([ref])
        #expect(!FileManager.default.fileExists(atPath: files.imageURL(for: ref).path))
    }
}
