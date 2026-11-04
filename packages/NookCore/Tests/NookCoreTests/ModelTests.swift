import Foundation
import Testing
@testable import NookCore

struct NoteTests {
    @Test func previewSkipsMarkdownMarkers() {
        #expect(Note(title: "x", body: "\n\n## Heading\n- [ ] Pack bags", category: .life).preview == "Heading")
        #expect(Note(title: "x", body: "  \n- [x] Book flights\nmore", category: .life).preview == "Book flights")
        #expect(Note(title: "x", body: "> Quote", category: .life).preview == "Quote")
        #expect(Note(title: "x", category: .life).preview == "")
    }

    @Test func blankNotes() {
        #expect(Note(title: "  ", body: "\n", category: .work).isBlank)
        #expect(Note(title: "", category: .work, checklist: [ChecklistItem(text: " ")]).isBlank)
        #expect(!Note(title: "", category: .work, checklist: [ChecklistItem(text: "Milk")]).isBlank)
        #expect(!Note(title: "", category: .work, attachments: [FileRef(name: "a.pdf", kind: .pdf)]).isBlank)
        #expect(!Note(title: "Idea", category: .work).isBlank)
    }

    @Test func countsCompletedItems() {
        let note = Note(title: "Trip", category: .travel, checklist: [
            ChecklistItem(text: "Book flights", isDone: true),
            ChecklistItem(text: "Reserve hotels"),
            ChecklistItem(text: "Plan daily itinerary"),
        ])
        #expect(note.completedChecklistCount == 1)
    }

    @Test func updatedAtDefaultsToCreatedAt() {
        let created = Date(timeIntervalSince1970: 1_793_721_600)
        #expect(Note(title: "x", category: .life, createdAt: created).updatedAt == created)
    }
}

struct TripPlanTests {
    let trip = TripPlan(title: "Japan Trip", startDate: Fixtures.day(2026, 11, 4), endDate: Fixtures.day(2026, 11, 10))

    @Test func countsDaysInclusively() {
        #expect(trip.dayCount == 7)
        #expect(trip.dayNumber(of: Fixtures.day(2026, 11, 3)) == nil)
        #expect(trip.dayNumber(of: Fixtures.day(2026, 11, 4)) == 1)
        #expect(trip.dayNumber(of: Fixtures.day(2026, 11, 10)) == 7)
        #expect(trip.dayNumber(of: Fixtures.day(2026, 11, 11)) == nil)
    }

    @Test func phaseDependsOnToday() {
        #expect(trip.phase(on: Fixtures.day(2026, 11, 3)) == .upcoming)
        #expect(trip.phase(on: Fixtures.day(2026, 11, 4)) == .ongoing)
        #expect(trip.phase(on: Fixtures.day(2026, 11, 10)) == .ongoing)
        #expect(trip.phase(on: Fixtures.day(2026, 11, 11)) == .finished)
    }

    @Test func endNeverPrecedesStart() {
        let backwards = TripPlan(title: "Oops", startDate: Fixtures.day(2026, 11, 4), endDate: Fixtures.day(2026, 11, 1))
        #expect(backwards.endDate == backwards.startDate)
        #expect(backwards.dayCount == 1)
    }
}

struct LedgerEntryTests {
    @Test func signedAmountFollowsTheKind() {
        let at = Fixtures.time(2026, 11, 4, 12)
        #expect(Fixtures.expense(500, .food, at: at).signedAmount == Fixtures.usd(-500))
        #expect(Fixtures.expense(500, .salary, at: at, kind: .income).signedAmount == Fixtures.usd(500))
        #expect(Fixtures.expense(500, .others, at: at, kind: .transfer).signedAmount == Fixtures.usd(0))
    }

    @Test func amountSetterUpdatesBothFields() {
        var entry = Fixtures.expense(500, .food, at: Fixtures.time(2026, 11, 4, 12))
        entry.amount = Money(minorUnits: 900, currencyCode: "eur")
        #expect(entry.amountMinor == 900)
        #expect(entry.currencyCode == "EUR")
    }
}
