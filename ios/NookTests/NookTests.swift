import Foundation
import Testing
import NookCore
@testable import Nook

/// The sample data has to reproduce the numbers in the reference design.
struct SampleDataTests {
    private let zone = TimeZone(secondsFromGMT: 8 * 3600)!
    /// A Wednesday.
    private let today = LocalDate(year: 2026, month: 11, day: 4)!

    private var sample: SampleData {
        SampleData.make(now: today.date(hour: 10, minute: 30, in: zone), timeZone: zone)
    }

    @Test func monthAddsUpToTheReferenceTotal() {
        let month = FinanceStats.monthToDate(sample.ledger, today: today, currencyCode: "USD", timeZone: zone)
        #expect(month.current.minorUnits == 128_050)
    }

    @Test(arguments: [1, 15, 28, 31])
    func monthTotalHoldsOnAnyDay(day: Int) throws {
        let date = try #require(LocalDate(year: 2026, month: 12, day: day))
        let sample = SampleData.make(now: date.date(hour: 12, in: zone), timeZone: zone)
        let month = FinanceStats.monthToDate(sample.ledger, today: date, currencyCode: "USD", timeZone: zone)
        #expect(month.current.minorUnits == 128_050)
    }

    @Test func weekMatchesTheReference() throws {
        let ledger = sample.ledger
        let week = FinanceStats.weekToDate(ledger, today: today, currencyCode: "USD", timeZone: zone)
        #expect(week.current.minorUnits == 58_020)
        let change = try #require(week.change)
        #expect(abs(change + 0.086) < 0.0005)

        let days = today.isoWeek
        let interval = DateInterval(start: days[0].startDate(in: zone), end: days[6].adding(days: 1).startDate(in: zone))
        let shares = FinanceStats.categoryBreakdown(ledger, in: interval, currencyCode: "USD")
        #expect(shares.map(\.category) == [.food, .travel, .shopping, .others])
        #expect(shares.map(\.amount.minorUnits) == [23_640, 18_000, 8_980, 7_400])

        let totals = FinanceStats.dailyTotals(ledger, days: days, currencyCode: "USD", timeZone: zone).map(\.total.minorUnits)
        #expect(totals.max() == totals[2], "today should be the tallest bar")
    }

    @Test func todayHasTheTwoReferenceEvents() {
        let titles = ScheduleQuery.events(sample.events, on: today, timeZone: zone).map(\.title)
        #expect(titles == ["Team Meeting", "Flight to Tokyo"])
    }

    @Test func notesAndVaultMatchTheReference() {
        let recent = sample.notes.max { $0.updatedAt < $1.updatedAt }
        #expect(recent?.title == "Trip Plan – Japan")
        #expect(sample.vaultItems.count == 12)
        #expect(sample.vaultItems.filter { $0.category == .account }.count == 7)
        #expect(Set(sample.vaultItems.map(\.category)).count == 3)
    }
}

@MainActor
struct AppStoreTests {
    private func makeStore() -> AppStore {
        AppStore(seed: SampleData.make())
    }

    @Test func blankNotesAreDiscarded() {
        let store = makeStore()
        let count = store.notes.count
        let note = store.createNote()
        #expect(store.notes.count == count + 1)
        store.discardIfBlank(note.id)
        #expect(store.notes.count == count)
    }

    @Test func savingMovesTheEditTimeOnlyOnChanges() throws {
        let store = makeStore()
        let original = try #require(store.recentNote)
        store.saveNote(original)
        #expect(store.note(id: original.id)?.updatedAt == original.updatedAt)

        var edited = original
        edited.title = "Trip Plan – Japan (final)"
        store.saveNote(edited)
        let saved = try #require(store.note(id: original.id))
        #expect(saved.title == edited.title)
        #expect(saved.updatedAt > original.updatedAt)
    }

    @Test func togglingATodoUpdatesItsNote() throws {
        let store = makeStore()
        let todo = try #require(store.openTodos(limit: 1).first)
        store.toggleChecklistItem(todo.item.id, in: todo.noteID)
        let item = store.note(id: todo.noteID)?.checklist.first { $0.id == todo.item.id }
        #expect(item?.isDone == true)
    }

    @Test func backupLeavesOutTheVault() throws {
        let store = makeStore()
        let backup = store.makeBackup()
        #expect(backup.notes.count == store.notes.count)
        let text = String(decoding: try backup.encoded(), as: UTF8.self)
        #expect(!text.contains("alex@example.com"))
    }
}

@MainActor
struct RouterTests {
    @Test func tappingTheCurrentTabGoesBackToItsFirstScreen() {
        let router = AppRouter()
        router.push(.transactions, in: .finance)
        #expect(router.selectedTab == .finance)
        #expect(!router.isTabBarVisible)
        router.select(.finance)
        #expect(router.financePath.isEmpty)
        #expect(router.isTabBarVisible)
    }

    @Test func newNotesOpenInTheNotesTab() {
        let router = AppRouter()
        let store = AppStore(seed: SampleData.make())
        router.perform(.note, store: store)
        #expect(router.selectedTab == .notes)
        #expect(router.notesPath.count == 1)
    }

    @Test func changeBadgeShowsTheDirection() {
        #expect(ChangeBadge.percentText(0.125).hasPrefix("+"))
        #expect(ChangeBadge.percentText(-0.086).contains("8.6"))
        #expect(!ChangeBadge.percentText(-0.086).hasPrefix("+"))
    }
}

struct FormattingTests {
    @Test func clockUsesTwentyFourHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        #expect(TimeText.time(Date(timeIntervalSince1970: 14 * 3600 + 30 * 60), calendar: calendar) == "14:30")
        #expect(TimeText.time(Date(timeIntervalSince1970: 9 * 3600 + 5 * 60), calendar: calendar) == "09:05")
    }
}
