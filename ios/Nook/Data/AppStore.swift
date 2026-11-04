import Foundation
import Observation
import NookCore

/// An unfinished checklist item, shown on the home screen.
struct OpenTodo: Identifiable, Hashable {
    let noteID: UUID
    let noteTitle: String
    let item: ChecklistItem
    var id: UUID { item.id }
}

struct NextAnniversary: Hashable {
    let anniversary: Anniversary
    let date: LocalDate
    let days: Int
}

/// The app's data. In P0 everything lives in memory and starts from sample data; changes are
/// also written through NookCore's `Repository` protocol so P1 can swap in SQLite (GRDB)
/// without touching the screens.
@MainActor @Observable
final class AppStore {
    private(set) var notes: [Note]
    private(set) var events: [ScheduleEvent]
    private(set) var trips: [TripPlan]
    private(set) var anniversaries: [Anniversary]
    private(set) var ledger: [LedgerEntry]
    private(set) var vaultItems: [VaultItem]

    let currencyCode: String
    let monthlyBudget: Money

    private let noteRepository: any Repository<Note>
    private let eventRepository: any Repository<ScheduleEvent>
    private let ledgerRepository: any Repository<LedgerEntry>

    init(seed: SampleData, currencyCode: String = "USD", monthlyBudgetMinor: Int64 = 200_000) {
        notes = seed.notes
        events = seed.events
        trips = seed.trips
        anniversaries = seed.anniversaries
        ledger = seed.ledger
        vaultItems = seed.vaultItems
        self.currencyCode = currencyCode
        monthlyBudget = Money(minorUnits: monthlyBudgetMinor, currencyCode: currencyCode)
        noteRepository = InMemoryRepository(seed.notes)
        eventRepository = InMemoryRepository(seed.events)
        ledgerRepository = InMemoryRepository(seed.ledger)
    }

    var timeZone: TimeZone { .current }

    /// Runs a repository write in the background. The arrays above stay the source the screens
    /// read; the in-memory repository used in P0 cannot fail.
    private func persist(_ work: @escaping @Sendable () async throws -> Void) {
        Task {
            try? await work()
        }
    }

    // MARK: - Notes

    func note(id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    var recentNote: Note? {
        notes.filter { !$0.isBlank }.max { $0.updatedAt < $1.updatedAt }
    }

    /// Stores an edited note. The edit time only moves when something actually changed.
    func saveNote(_ note: Note) {
        var saved = note
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            guard notes[index] != note else { return }
            saved.updatedAt = Date()
            notes[index] = saved
        } else {
            notes.append(saved)
        }
        let repository = noteRepository
        let record = saved
        persist { try await repository.upsert(record) }
    }

    func createNote(category: NoteCategory = .personal) -> Note {
        let note = Note(title: "", category: category)
        notes.append(note)
        return note
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        let repository = noteRepository
        persist { try await repository.delete(id: id) }
    }

    /// Drops a note that was opened but never written in.
    func discardIfBlank(_ id: UUID) {
        if let note = note(id: id), note.isBlank {
            deleteNote(id)
        }
    }

    func togglePin(_ id: UUID) {
        guard var updated = note(id: id) else { return }
        updated.isPinned.toggle()
        saveNote(updated)
    }

    func toggleChecklistItem(_ itemID: UUID, in noteID: UUID) {
        guard var updated = note(id: noteID),
              let index = updated.checklist.firstIndex(where: { $0.id == itemID }) else { return }
        updated.checklist[index].isDone.toggle()
        saveNote(updated)
    }

    func openTodos(limit: Int) -> [OpenTodo] {
        var result: [OpenTodo] = []
        for note in notes.sorted(by: NoteQuery.displayOrder) {
            for item in note.checklist where !item.isDone && !item.text.isEmpty {
                result.append(OpenTodo(noteID: note.id, noteTitle: note.displayTitle, item: item))
                if result.count == limit {
                    return result
                }
            }
        }
        return result
    }

    var openTodoCount: Int {
        notes.reduce(0) { count, note in
            count + note.checklist.filter { !$0.isDone && !$0.text.isEmpty }.count
        }
    }

    // MARK: - Schedule

    func event(id: UUID) -> ScheduleEvent? {
        events.first { $0.id == id }
    }

    func events(on day: LocalDate) -> [ScheduleEvent] {
        ScheduleQuery.events(events, on: day, timeZone: timeZone)
    }

    func eventDays(in days: [LocalDate]) -> Set<LocalDate> {
        ScheduleQuery.daysWithEvents(events, in: days, timeZone: timeZone)
    }

    /// Today's events that have not finished yet.
    func reminders(now: Date) -> [ScheduleEvent] {
        let today = LocalDate.today(in: timeZone, now: now)
        return ScheduleQuery.upcoming(events, after: now).filter {
            LocalDate($0.start, timeZone: timeZone) == today
        }
    }

    func saveEvent(_ event: ScheduleEvent) {
        var saved = event
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            guard events[index] != event else { return }
            saved.updatedAt = Date()
            events[index] = saved
        } else {
            events.append(saved)
        }
        let repository = eventRepository
        let record = saved
        persist { try await repository.upsert(record) }
    }

    func deleteEvent(_ id: UUID) {
        events.removeAll { $0.id == id }
        let repository = eventRepository
        persist { try await repository.delete(id: id) }
    }

    var tripsByDate: [TripPlan] {
        trips.sorted { $0.startDate < $1.startDate }
    }

    func events(inTrip trip: TripPlan) -> [ScheduleEvent] {
        events.filter { $0.planID == trip.id }.sorted(by: ScheduleQuery.agendaOrder)
    }

    func anniversariesByNextDate(today: LocalDate) -> [Anniversary] {
        anniversaries.sorted { lhs, rhs in
            switch (lhs.nextOccurrence(onOrAfter: today), rhs.nextOccurrence(onOrAfter: today)) {
            case let (left?, right?): return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.date > rhs.date
            }
        }
    }

    func nextAnniversary(today: LocalDate) -> NextAnniversary? {
        anniversaries
            .compactMap { anniversary -> NextAnniversary? in
                guard let date = anniversary.nextOccurrence(onOrAfter: today) else { return nil }
                return NextAnniversary(anniversary: anniversary, date: date, days: today.days(to: date))
            }
            .min { $0.days < $1.days }
    }

    // MARK: - Finance

    var recentEntries: [LedgerEntry] {
        ledger.sorted { $0.occurredAt > $1.occurredAt }
    }

    func addEntry(_ entry: LedgerEntry) {
        ledger.append(entry)
        let repository = ledgerRepository
        persist { try await repository.upsert(entry) }
    }

    func deleteEntry(_ id: UUID) {
        ledger.removeAll { $0.id == id }
        let repository = ledgerRepository
        persist { try await repository.delete(id: id) }
    }

    /// From the start of the first day to the start of the day after the last.
    func interval(for days: [LocalDate]) -> DateInterval {
        guard let first = days.first, let last = days.last else {
            return DateInterval(start: Date(), duration: 0)
        }
        return DateInterval(start: first.startDate(in: timeZone), end: last.adding(days: 1).startDate(in: timeZone))
    }

    func monthDays(of today: LocalDate) -> [LocalDate] {
        let start = today.startOfMonth
        let count = LocalDate.daysInMonth(year: today.year, month: today.month)
        return (0..<count).map { start.adding(days: $0) }
    }

    func weekToDate(today: LocalDate) -> PeriodComparison {
        FinanceStats.weekToDate(ledger, today: today, currencyCode: currencyCode, timeZone: timeZone)
    }

    func monthToDate(today: LocalDate) -> PeriodComparison {
        FinanceStats.monthToDate(ledger, today: today, currencyCode: currencyCode, timeZone: timeZone)
    }

    func dailyTotals(days: [LocalDate]) -> [DailyTotal] {
        FinanceStats.dailyTotals(ledger, days: days, currencyCode: currencyCode, timeZone: timeZone)
    }

    func breakdown(in interval: DateInterval) -> [CategoryShare] {
        FinanceStats.categoryBreakdown(ledger, in: interval, currencyCode: currencyCode)
    }

    /// Running month total at 7 points, for the small bars on the home card.
    func monthSeries(today: LocalDate) -> [DailyTotal] {
        FinanceStats.cumulativeSeries(ledger, through: today, currencyCode: currencyCode, timeZone: timeZone)
    }

    // MARK: - Vault (P0 shell: no secrets are stored)

    func vaultItem(id: UUID) -> VaultItem? {
        vaultItems.first { $0.id == id }
    }

    func vaultItems(in category: VaultCategory?) -> [VaultItem] {
        guard let category else { return vaultItems }
        return vaultItems.filter { $0.category == category }
    }

    var vaultCategoryCount: Int {
        Set(vaultItems.map(\.category)).count
    }

    func searchVault(_ text: String) -> [VaultItem] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vaultItems }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return vaultItems.filter {
            $0.title.range(of: query, options: options) != nil || $0.subtitle.range(of: query, options: options) != nil
        }
    }

    // MARK: - Backup

    /// Notes, schedule and finance records. The vault is never included.
    func makeBackup(now: Date = Date()) -> NookBackup {
        NookBackup(
            exportedAt: now,
            notes: notes.filter { !$0.isBlank },
            events: events,
            trips: trips,
            anniversaries: anniversaries,
            ledger: ledger
        )
    }

    func writeBackupFile(now: Date = Date()) throws -> URL {
        let data = try makeBackup(now: now).encoded()
        let day = LocalDate.today(in: timeZone, now: now)
        let url = FileManager.default.temporaryDirectory.appending(path: "Nook-Backup-\(day.isoString).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
