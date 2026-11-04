import Foundation
import Testing
@testable import NookCore

/// Field names follow spec §6.2, so the records can later travel inside sync envelopes unchanged.
struct ModelCodingTests {
    private static let created = Date(timeIntervalSince1970: 1_793_721_600)
    private static let planID = UUID(uuidString: "0190A5B2-0000-7000-8000-000000000001")!

    private func expectKeys(_ keys: [String], in json: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for key in keys {
            #expect(json.contains(key), "missing \(key) in \(json)", sourceLocation: sourceLocation)
        }
    }

    @Test func note() throws {
        let note = Note(
            title: "Trip Plan – Japan",
            body: "Pack light",
            category: .travel,
            tags: ["japan"],
            isPinned: true,
            checklist: [ChecklistItem(text: "Book flights", isDone: true)],
            attachments: [FileRef(name: "fuji.jpg", kind: .image, byteCount: 2_048)],
            createdAt: Self.created
        )
        let json = try Fixtures.jsonText(note)
        expectKeys([
            #""pinned":true"#, #""todos":["#, #""done":true"#, #""file_refs":["#, #""size":2048"#,
            #""category":"travel""#, #""created_at":"2026-11-03T16:00:00.000Z""#, #""updated_at":"2026-11-03T16:00:00.000Z""#,
        ], in: json)
        #expect(try Fixtures.decode(Note.self, from: json) == note)
    }

    @Test func event() throws {
        let event = ScheduleEvent(
            title: "Flight to Tokyo",
            start: Fixtures.time(2026, 11, 4, 14, 30),
            end: Fixtures.time(2026, 11, 4, 18, 45),
            category: .travel,
            reminderMinutes: 60,
            planID: Self.planID,
            createdAt: Self.created
        )
        let json = try Fixtures.jsonText(event)
        expectKeys([
            #""all_day":false"#, #""reminder_minutes":60"#, #""plan_id":"0190A5B2-0000-7000-8000-000000000001""#,
            #""start":"2026-11-04T06:30:00.000Z""#, #""end":"2026-11-04T10:45:00.000Z""#,
        ], in: json)
        #expect(!json.contains("location"))
        #expect(try Fixtures.decode(ScheduleEvent.self, from: json) == event)
    }

    @Test func trip() throws {
        let trip = TripPlan(
            title: "Japan Trip", destination: "Tokyo",
            startDate: Fixtures.day(2026, 11, 4), endDate: Fixtures.day(2026, 11, 10),
            createdAt: Self.created
        )
        let json = try Fixtures.jsonText(trip)
        expectKeys([#""start_date":"2026-11-04""#, #""end_date":"2026-11-10""#, #""destination":"Tokyo""#], in: json)
        #expect(try Fixtures.decode(TripPlan.self, from: json) == trip)
    }

    @Test func anniversary() throws {
        let anniversary = Anniversary(
            title: "Launch", date: Fixtures.day(2026, 1, 1), repeatRule: .never, kind: .project,
            notes: "v1", createdAt: Self.created
        )
        let json = try Fixtures.jsonText(anniversary)
        expectKeys([
            #""repeat_rule":"none""#, #""category":"project""#, #""description":"v1""#,
            #""show_countdown":true"#, #""date":"2026-01-01""#,
        ], in: json)
        #expect(try Fixtures.decode(Anniversary.self, from: json) == anniversary)
    }

    @Test func ledgerEntry() throws {
        let entry = Fixtures.expense(23_640, .food, at: Fixtures.time(2026, 11, 4, 12))
        let json = try Fixtures.jsonText(entry)
        expectKeys([
            #""type":"expense""#, #""amount_minor":23640"#, #""currency":"USD""#,
            #""category":"food""#, #""occurred_at":"2026-11-04T04:00:00.000Z""#,
        ], in: json)
        #expect(try Fixtures.decode(LedgerEntry.self, from: json) == entry)
    }

    @Test func vaultItemHasNoSecretFields() throws {
        let item = VaultItem(
            title: "Bank", subtitle: "***** 4589", category: .card, icon: "building.columns",
            isFavorite: true, createdAt: Self.created
        )
        let json = try Fixtures.jsonText(item)
        #expect(try Fixtures.topLevelKeys(Data(json.utf8)) == [
            "id", "name", "subtitle", "category", "icon", "favorite", "created_at", "updated_at",
        ])
        #expect(try Fixtures.decode(VaultItem.self, from: json) == item)
    }
}
