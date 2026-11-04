import Foundation
import GRDB
import Testing
import NookCore
@testable import Nook

@MainActor
struct StorageSafetyTests {
    private func store(_ database: AppDatabase, attachments: AttachmentStore = .makeTemporary()) -> AppStore {
        let defaults = UserDefaults(suiteName: "nook.tests.\(UUID().uuidString)")!
        defaults.set(false, forKey: "vault.quickUnlock")
        return AppStore(database: database, attachments: attachments, defaults: defaults, vaultParameters: .testing)
    }

    @Test func failedPhotoRemovalKeepsTheFilesAndSavedReference() throws {
        let writer = try DatabaseQueue()
        let database = try AppDatabase(writer)
        let attachments = AttachmentStore.makeTemporary()
        defer { try? FileManager.default.removeItem(at: attachments.folder) }
        let store = store(database, attachments: attachments)
        let ref = FileRef(name: "test.jpg", kind: .image, byteCount: 3)
        try Data([1, 2, 3]).write(to: attachments.imageURL(for: ref))
        try Data([1]).write(to: attachments.thumbnailURL(for: ref))
        var note = Note(title: "Photo", category: .personal)
        note.attachments = [ref]
        #expect(store.saveNote(note))
        try writer.close()
        note.attachments = []
        #expect(!store.saveNote(note))
        #expect(store.saveFailures == 1)
        #expect(store.note(id: note.id)?.attachments == [ref])
        #expect(FileManager.default.fileExists(atPath: attachments.imageURL(for: ref).path))
        #expect(FileManager.default.fileExists(atPath: attachments.thumbnailURL(for: ref).path))
    }

    @Test func committedPhotoRemovalCleansBothFiles() throws {
        let database = try AppDatabase.makeInMemory()
        let attachments = AttachmentStore.makeTemporary()
        defer { try? FileManager.default.removeItem(at: attachments.folder) }
        let store = store(database, attachments: attachments)
        let ref = FileRef(name: "test.jpg", kind: .image, byteCount: 3)
        try Data([1, 2, 3]).write(to: attachments.imageURL(for: ref))
        try Data([1]).write(to: attachments.thumbnailURL(for: ref))
        var note = Note(title: "Photo", category: .personal)
        note.attachments = [ref]
        #expect(store.saveNote(note))
        note.attachments = []
        #expect(store.saveNote(note))
        #expect(try database.loadSnapshot().notes.first?.attachments.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: attachments.imageURL(for: ref).path))
        #expect(!FileManager.default.fileExists(atPath: attachments.thumbnailURL(for: ref).path))
    }

    @Test func tripDeletionAndUnlinkingRollBackTogether() throws {
        let database = try AppDatabase.makeInMemory()
        let store = store(database)
        let day = LocalDate(year: 2026, month: 11, day: 4)!
        let trip = TripPlan(title: "Trip", startDate: day, endDate: day)
        #expect(store.saveTrip(trip))
        var event = ScheduleEvent(title: "Flight", start: Date())
        event.planID = trip.id
        #expect(store.saveEvent(event))
        try database.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_trip_delete BEFORE DELETE ON trip BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        #expect(!store.deleteTrip(trip.id))
        #expect(store.trip(id: trip.id) != nil)
        #expect(store.event(id: event.id)?.planID == trip.id)
        #expect(try database.loadSnapshot().events.first?.planID == trip.id)
        try database.writer.write { db in try db.execute(sql: "DROP TRIGGER reject_trip_delete") }
        #expect(store.deleteTrip(trip.id))
        #expect(store.trip(id: trip.id) == nil)
        #expect(store.event(id: event.id)?.planID == nil)
        #expect(try database.loadSnapshot().events.first?.planID == nil)
    }
}
