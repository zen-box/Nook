import Foundation
import Testing
@testable import NookCore

struct BackupTests {
    private static func sample() -> NookBackup {
        let created = Date(timeIntervalSince1970: 1_793_721_600)
        var generator = SplitMix64(seed: 2026)
        func id() -> UUID {
            UUIDv7.make(timestamp: created, using: &generator)
        }
        let trip = TripPlan(
            id: id(), title: "Japan Trip", destination: "Tokyo",
            startDate: Fixtures.day(2026, 11, 4), endDate: Fixtures.day(2026, 11, 10), createdAt: created
        )
        return NookBackup(
            exportedAt: Date(timeIntervalSince1970: 1_793_725_200.5),
            notes: [
                Note(
                    id: id(), title: "Trip Plan – Japan", body: "Pack light", category: .travel, isPinned: true,
                    checklist: [ChecklistItem(id: id(), text: "Book flights", isDone: true)], createdAt: created
                ),
            ],
            events: [
                ScheduleEvent(
                    id: id(), title: "Flight to Tokyo", start: Fixtures.time(2026, 11, 4, 14, 30),
                    category: .travel, planID: trip.id, createdAt: created
                ),
            ],
            trips: [trip],
            anniversaries: [Anniversary(id: id(), title: "Leap Friend", date: Fixtures.day(2024, 2, 29), kind: .birthday, createdAt: created)],
            ledger: [Fixtures.expense(128_050, .shopping, at: Fixtures.time(2026, 11, 2, 18))]
        )
    }

    @Test func roundTrips() throws {
        let backup = Self.sample()
        #expect(try NookBackup.decode(backup.encoded()) == backup)
    }

    @Test func usesSpecNamesAndLeavesOutTheVault() throws {
        struct Header: Decodable {
            var format: String
            var version: Int
        }
        let data = try Self.sample().encoded()
        #expect(try Fixtures.topLevelKeys(data) == [
            "format", "version", "exported_at", "notes", "events", "plans", "anniversaries", "transactions",
        ])
        let header = try JSONDecoder().decode(Header.self, from: data)
        #expect(header.format == "nook.backup")
        #expect(header.version == 1)
        #expect(!String(decoding: data, as: UTF8.self).contains("vault"))
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: NookBackup.ReadError.notANookBackup) {
            try NookBackup.decode(Data("not json".utf8))
        }
        #expect(throws: NookBackup.ReadError.notANookBackup) {
            try NookBackup.decode(Data(#"{"hello":"world"}"#.utf8))
        }
        #expect(throws: NookBackup.ReadError.notANookBackup) {
            try NookBackup.decode(Data(#"{"format":"other","version":1}"#.utf8))
        }
        #expect(throws: NookBackup.ReadError.unsupportedVersion(2)) {
            try NookBackup.decode(Data(#"{"format":"nook.backup","version":2}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try NookBackup.decode(Data(#"{"format":"nook.backup","version":1}"#.utf8))
        }
    }
}
