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

    @Test func vaultItem() throws {
        let item = VaultItem(
            title: "Bank", category: .card, icon: "building.columns", isFavorite: true,
            url: "https://bank.example", notes: "Branch 12",
            fields: [VaultField(label: "Number", value: "4111 1111 1111 4589", isSecret: true)],
            createdAt: Self.created
        )
        let json = try Fixtures.jsonText(item)
        #expect(try Fixtures.topLevelKeys(Data(json.utf8)) == [
            "id", "name", "category", "icon", "favorite", "url", "notes", "fields", "created_at", "updated_at",
        ])
        expectKeys([#""secret":true"#, #""label":"Number""#], in: json)
        #expect(try Fixtures.decode(VaultItem.self, from: json) == item)
    }
}

struct VaultItemTests {
    private func item(_ category: VaultCategory, _ fields: [VaultField]) -> VaultItem {
        VaultItem(title: "Item", category: category, icon: "key", fields: fields)
    }

    @Test func subtitleShowsTheFirstVisibleField() {
        let login = item(.account, [
            VaultField(label: "Password", value: "hunter2", isSecret: true),
            VaultField(label: "Username", value: "  alex@example.com "),
        ])
        #expect(login.subtitle == "alex@example.com")
        #expect(item(.account, [VaultField(label: "Password", value: "x", isSecret: true)]).subtitle.isEmpty)
    }

    @Test func cardsShowTheLastFourDigits() {
        let card = item(.card, [
            VaultField(label: "Cardholder", value: "Alex Lin"),
            VaultField(label: "Number", value: "4111 1111 1111 4589", isSecret: true),
            VaultField(label: "CVV", value: "123", isSecret: true),
        ])
        #expect(card.subtitle == "•••• 4589")
        #expect(card.primarySecret?.label == "Number")
    }

    @Test func searchSkipsSecretValues() {
        let login = item(.account, [
            VaultField(label: "Username", value: "alex@example.com"),
            VaultField(label: "Password", value: "correct horse", isSecret: true),
        ])
        #expect(login.matches("ALEX example"))
        #expect(login.matches(""))
        #expect(!login.matches("horse"))
    }
}

struct PasswordGeneratorTests {
    @Test(arguments: [4, 12, 20, 64])
    func usesOnlyAllowedCharacters(length: Int) {
        var generator = SplitMix64(seed: UInt64(length))
        let password = PasswordGenerator.make(length: length, includeSymbols: true, using: &generator)
        let allowed = Set(PasswordGenerator.letters + PasswordGenerator.digits + PasswordGenerator.symbols)
        #expect(password.count == length)
        #expect(password.allSatisfy { allowed.contains($0) })
        #expect(password.contains { PasswordGenerator.digits.contains($0) })
        #expect(password.contains { PasswordGenerator.letters.contains($0) })
        #expect(password.contains { PasswordGenerator.symbols.contains($0) })
    }

    @Test func canLeaveOutSymbols() {
        var generator = SplitMix64(seed: 7)
        let password = PasswordGenerator.make(length: 30, includeSymbols: false, using: &generator)
        #expect(!password.contains { PasswordGenerator.symbols.contains($0) })
    }

    @Test func systemPasswordsDiffer() {
        #expect(PasswordGenerator.make() != PasswordGenerator.make())
        #expect(PasswordGenerator.make().count == 20)
    }
}
