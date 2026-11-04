import Foundation
import Testing
@testable import NookCore

struct NoteQueryTests {
    private static let now = Date(timeIntervalSince1970: 1_793_721_600)

    private static func note(
        _ title: String,
        body: String = "",
        category: NoteCategory = .life,
        tags: [String] = [],
        pinned: Bool = false,
        checklist: [String] = [],
        hoursAgo: Double
    ) -> Note {
        Note(
            title: title, body: body, category: category, tags: tags, isPinned: pinned,
            checklist: checklist.map { ChecklistItem(text: $0) },
            createdAt: now.addingTimeInterval(-hoursAgo * 3600)
        )
    }

    private static let notes = [
        note("Trip Plan – Japan", body: "Visit the café in Kyoto", category: .travel, pinned: true,
             checklist: ["Book flights", "Reserve hotels"], hoursAgo: 48),
        note("Project Ideas", body: "New features for the organizer app", category: .work, tags: ["roadmap"], hoursAgo: 96),
        note("Reading List", body: "Books, articles, and resources", hoursAgo: 144),
        note("Grocery List", checklist: ["Milk", "Eggs"], hoursAgo: 1),
    ]

    private func titles(_ search: String = "", _ category: NoteCategory? = nil) -> [String] {
        NoteQuery.filter(Self.notes, search: search, category: category).map(\.title)
    }

    @Test func emptySearchListsPinnedThenRecent() {
        #expect(titles() == ["Trip Plan – Japan", "Grocery List", "Project Ideas", "Reading List"])
        #expect(titles("   ") == titles())
    }

    @Test func everyWordMustMatch() {
        #expect(titles("list") == ["Grocery List", "Reading List"])
        #expect(titles("list grocery") == ["Grocery List"])
        #expect(titles("list japan").isEmpty)
    }

    @Test func ignoresCaseAndAccents() {
        #expect(titles("CAFE") == ["Trip Plan – Japan"])
        #expect(titles("café") == ["Trip Plan – Japan"])
        #expect(titles("kyoto TRIP") == ["Trip Plan – Japan"])
    }

    @Test func searchesChecklistAndTags() {
        #expect(titles("eggs") == ["Grocery List"])
        #expect(titles("hotels") == ["Trip Plan – Japan"])
        #expect(titles("roadmap") == ["Project Ideas"])
    }

    @Test func filtersByCategory() {
        #expect(titles("", .life) == ["Grocery List", "Reading List"])
        #expect(titles("list", .travel).isEmpty)
    }
}
