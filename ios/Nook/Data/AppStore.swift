import Foundation
import Observation
import NookCore
@preconcurrency import UserNotifications

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

/// The app's data. Everything is read from the SQLite database at launch and every change is
/// written straight back, so nothing is lost when the app closes. The screens read the arrays
/// below; the database is the copy that lasts.
@MainActor @Observable
final class AppStore {
    private(set) var notes: [Note] = []
    private(set) var events: [ScheduleEvent] = []
    private(set) var trips: [TripPlan] = []
    private(set) var anniversaries: [Anniversary] = []
    private(set) var ledger: [LedgerEntry] = []
    private(set) var tasks: [TaskItem] = []
    var dataRevision = 0

    /// Goes up each time a change could not be saved, so the screen can say so.
    private(set) var saveFailures = 0
    /// True when the database could not be opened: changes then only last until the app quits.
    let isTemporary: Bool

    /// Shown on the avatar; empty until set in Settings.
    var displayName: String {
        didSet { defaults.set(displayName, forKey: Keys.displayName) }
    }

    var currencyCode: String {
        didSet { defaults.set(currencyCode, forKey: Keys.currency) }
    }

    /// In minor units of `currencyCode`; 0 means no budget.
    var monthlyBudgetMinor: Int64 {
        didSet { defaults.set(Int(monthlyBudgetMinor), forKey: Keys.budget) }
    }

    let vault: VaultStore
    let attachments: AttachmentStore
    let database: AppDatabase
    let defaults: UserDefaults
    @ObservationIgnored private var reminderSync: Task<Void, Never>?
    @ObservationIgnored private var assistantStorage: AgentSession?
    @ObservationIgnored private var syncStorage: SyncCoordinator?
    var syncCoordinator: SyncCoordinator {
        if let syncStorage { return syncStorage }
        let coordinator = SyncCoordinator(store: self); syncStorage = coordinator; return coordinator
    }
    func installTransferredArchive(_ archive: StagedArchive, settings: S3TransferSettings?) throws {
        guard !syncCoordinator.isWorking else { throw SyncError.changedDuringSync }
        guard let settings else { try BackupArchive.install(archive, into: self); return }
        try SyncCrypto.validate(settings.state.library, key: settings.rootKey)
        guard settings.state.document.libraryID == settings.state.library.id else { throw SyncError.wrongLibrary }
        var incomingState = settings.state
        incomingState.configuration = settings.configuration
        let config = try JSONEncoder().encode(settings.configuration)
        let state = try NookJSON.makeEncoder().encode(incomingState)
        // Stage credentials under a fresh account. A single SQLite transaction selects
        // them together with the imported records/state; interruption keeps the old
        // connection selected. Neither phone's existing credentials are overwritten.
        let account = "sync.s3.\(UUID())"
        try SecretStore.write(settings.rootKey, account: "sync.root.\(settings.state.library.id)")
        try SecretStore.write(JSONEncoder().encode(settings.credentials), account: account)
        do {
            try Data().write(to: attachments.folder.appending(path: ".retain-sync-history"), options: .atomic)
            try BackupArchive.install(archive, into: self, syncState: state, credentialAccount: account)
        } catch { try? SecretStore.delete(account); throw error }
        defaults.set(config, forKey: "sync.configuration")
        syncStorage = nil
    }

    var assistantSession: AgentSession {
        if let assistantStorage { return assistantStorage }
        let session = AgentSession(read: { [weak self] in self?.assistantRecords() ?? [] }, commit: { [weak self] plan in
            guard let self else { throw AgentPlanError.missingRecord }
            try self.applyAssistantPlan(plan)
        }, currency: { [weak self] in self?.currencyCode ?? "CNY" }, reminderFeedback: { [weak self] in
            await self?.reminderSync?.value
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
                return String(localized: "Records saved, but notifications are not allowed. Enable Nook notifications in iOS Settings.")
            }
            if let error = UserDefaults.standard.string(forKey: "reminders.error") { return String(localized: "Records saved. ") + error }
            return String(localized: "Records saved and reminders scheduled.")
        })
        assistantStorage = session
        return session
    }

    private enum Keys {
        static let displayName = "profile.name"
        static let currency = "finance.currency"
        static let budget = "finance.monthlyBudget"
    }

    init(
        database: AppDatabase,
        attachments: AttachmentStore,
        defaults: UserDefaults = .standard,
        vaultParameters: VaultCrypto.KDFParameters = .standard,
        isTemporary: Bool = false
    ) {
        self.database = database
        self.attachments = attachments
        self.defaults = defaults
        self.isTemporary = isTemporary
        vault = VaultStore(database: database, defaults: defaults, parameters: vaultParameters)
        displayName = defaults.string(forKey: Keys.displayName) ?? ""
        currencyCode = defaults.string(forKey: Keys.currency) ?? Self.defaultCurrency
        monthlyBudgetMinor = Int64(defaults.integer(forKey: Keys.budget))
        reload()
    }

    /// The currency of the phone's region, such as CNY in mainland China.
    static var defaultCurrency: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var timeZone: TimeZone { .current }

    var monthlyBudget: Money? {
        monthlyBudgetMinor > 0 ? Money(minorUnits: monthlyBudgetMinor, currencyCode: currencyCode) : nil
    }

    var isEmpty: Bool {
        notes.isEmpty && events.isEmpty && trips.isEmpty && anniversaries.isEmpty && ledger.isEmpty && tasks.isEmpty
    }

    func reload() {
        do {
            let snapshot = try database.loadSnapshot()
            notes = snapshot.notes
            events = snapshot.events
            trips = snapshot.trips
            anniversaries = snapshot.anniversaries
            ledger = snapshot.ledger
            tasks = snapshot.tasks
        } catch {
            saveFailures += 1
        }
    }

    /// Runs a database write. On failure nothing in memory changes and the failure is counted.
    private func write(_ change: (AppDatabase) throws -> Void) -> Bool {
        do {
            try change(database)
            dataRevision += 1
            return true
        } catch {
            saveFailures += 1
            return false
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
    @discardableResult
    func saveNote(_ note: Note, retainingAttachments: [FileRef] = []) -> Bool {
        var saved = note
        let index = notes.firstIndex { $0.id == note.id }
        let previousAttachments = index.map { notes[$0].attachments } ?? []
        if let index {
            guard notes[index] != note else { return true }
            saved.updatedAt = Date()
        }
        guard write({ try $0.save(saved) }) else { return false }
        if let index {
            notes[index] = saved
        } else {
            notes.append(saved)
        }
        // Only remove files after their references have been removed from SQLite.
        for ref in previousAttachments where !retainingAttachments.contains(where: { $0.id == ref.id }) && !notes.contains(where: { $0.attachments.contains(where: { $0.id == ref.id }) }) {
            attachments.delete(ref)
        }
        return true
    }

    /// A blank note that is only stored once something is written in it.
    func createNote(category: NoteCategory = .personal) -> Note {
        let note = Note(title: "", category: category)
        notes.append(note)
        return note
    }

    @discardableResult
    func deleteNote(_ id: UUID) -> Bool {
        guard let existing = note(id: id) else { return true }
        let now = Date()
        guard write({ try $0.deleteNote(id, updatedAt: now) }) else { return false }
        notes.removeAll { $0.id == id }
        for ref in existing.attachments {
            if !notes.contains(where: { $0.attachments.contains(where: { $0.id == ref.id }) }) {
                attachments.delete(ref)
            }
        }
        for index in trips.indices where trips[index].noteID == id {
            trips[index].noteID = nil
            trips[index].updatedAt = now
        }
        return true
    }

    /// Drops a note that was opened but never written in.
    func discardIfBlank(_ id: UUID) {
        if let existing = note(id: id), existing.isBlank {
            deleteNote(id)
        }
    }

    func toggleChecklistItem(_ itemID: UUID, in noteID: UUID) {
        guard var updated = note(id: noteID) else { return }
        updated.toggleChecklistItem(itemID)
        saveNote(updated)
    }

    func storePhoto(_ data: Data) throws -> FileRef {
        try attachments.saveImage(data, name: "Photo.jpg")
    }

    func discardPhoto(_ ref: FileRef) {
        attachments.delete(ref)
    }

    /// Editor undo can restore removed photos until the editing session closes.
    func discardUnreferencedPhotos(_ refs: [FileRef]) {
        for ref in refs where !notes.contains(where: { $0.attachments.contains(where: { $0.id == ref.id }) }) {
            attachments.delete(ref)
        }
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
    func todaysAgenda(now: Date) -> [ScheduleEvent] {
        let today = LocalDate.today(in: timeZone, now: now)
        return events(on: today).filter { $0.effectiveEnd > now || $0.start >= now }
    }

    @discardableResult
    func saveEvent(_ event: ScheduleEvent) -> Bool {
        var saved = event
        let index = events.firstIndex { $0.id == event.id }
        if let index {
            guard events[index] != event else { return true }
            saved.updatedAt = Date()
        }
        guard write({ try $0.save(saved) }) else { return false }
        if let index {
            events[index] = saved
        } else {
            events.append(saved)
        }
        syncReminders()
        return true
    }

    @discardableResult
    func deleteEvent(_ id: UUID) -> Bool {
        guard write({ try $0.delete(ScheduleEvent.self, id: id) }) else { return false }
        events.removeAll { $0.id == id }
        syncReminders()
        return true
    }

    /// Rebuilds the system notifications for event reminders, one sync at a time.
    func syncReminders() {
        let events = self.events
        let tasks = self.tasks
        let anniversaries = self.anniversaries
        let previous = reminderSync
        reminderSync = Task {
            await previous?.value
            await ReminderScheduler.sync(events: events, tasks: tasks, anniversaries: anniversaries)
        }
    }

    func trip(id: UUID) -> TripPlan? {
        trips.first { $0.id == id }
    }

    var tripsByDate: [TripPlan] {
        trips.sorted { $0.startDate < $1.startDate }
    }

    func events(inTrip trip: TripPlan) -> [ScheduleEvent] {
        let range = DateInterval(start: trip.startDate.startDate(in: timeZone), end: trip.endDate.adding(days: 1).startDate(in: timeZone))
        return events.filter { $0.planID == trip.id }.flatMap { $0.occurrences(in: range) }.sorted(by: ScheduleQuery.agendaOrder)
    }

    @discardableResult
    func saveTrip(_ trip: TripPlan) -> Bool {
        var saved = trip
        let index = trips.firstIndex { $0.id == trip.id }
        if let index {
            guard trips[index] != trip else { return true }
            saved.updatedAt = Date()
        }
        guard write({ try $0.save(saved) }) else { return false }
        if let index {
            trips[index] = saved
        } else {
            trips.append(saved)
        }
        return true
    }

    @discardableResult
    func deleteTrip(_ id: UUID) -> Bool {
        let now = Date()
        guard write({ try $0.deleteTrip(id, updatedAt: now) }) else { return false }
        trips.removeAll { $0.id == id }
        for index in events.indices where events[index].planID == id {
            events[index].planID = nil
            events[index].updatedAt = now
        }
        syncReminders()
        return true
    }

    /// Creates a travel note for the trip and links it.
    func createPlanNote(for trip: TripPlan) -> Note? {
        let note = Note(title: String(localized: "Trip Plan – \(trip.title)"), category: .travel, isPinned: true)
        var linked = trip
        linked.noteID = note.id
        linked.updatedAt = Date()
        guard write({ try $0.savePlanNote(note, trip: linked) }) else { return nil }
        notes.append(note)
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = linked
        } else {
            trips.append(linked)
        }
        return note
    }

    func anniversary(id: UUID) -> Anniversary? {
        anniversaries.first { $0.id == id }
    }

    @discardableResult
    func saveAnniversary(_ anniversary: Anniversary) -> Bool {
        var saved = anniversary
        let index = anniversaries.firstIndex { $0.id == anniversary.id }
        if let index {
            guard anniversaries[index] != anniversary else { return true }
            saved.updatedAt = Date()
        }
        guard write({ try $0.save(saved) }) else { return false }
        if let index {
            anniversaries[index] = saved
        } else {
            anniversaries.append(saved)
        }
        syncReminders()
        return true
    }

    @discardableResult
    func deleteAnniversary(_ id: UUID) -> Bool {
        guard write({ try $0.delete(Anniversary.self, id: id) }) else { return false }
        anniversaries.removeAll { $0.id == id }
        syncReminders()
        return true
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

    func entry(id: UUID) -> LedgerEntry? {
        ledger.first { $0.id == id }
    }

    var recentEntries: [LedgerEntry] {
        ledger.sorted { $0.occurredAt > $1.occurredAt }
    }

    @discardableResult
    func saveEntry(_ entry: LedgerEntry) -> Bool {
        var saved = entry
        let index = ledger.firstIndex { $0.id == entry.id }
        if let index {
            guard ledger[index] != entry else { return true }
            saved.updatedAt = Date()
        }
        guard write({ try $0.save(saved) }) else { return false }
        if let index {
            ledger[index] = saved
        } else {
            ledger.append(saved)
        }
        return true
    }

    @discardableResult
    func deleteEntry(_ id: UUID) -> Bool {
        guard write({ try $0.delete(LedgerEntry.self, id: id) }) else { return false }
        ledger.removeAll { $0.id == id }
        return true
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

    // MARK: - Backup

    /// Notes, schedule and finance records. The vault and photos are not included.
    func makeBackup(now: Date = Date()) -> NookBackup {
        NookBackup(
            exportedAt: now,
            notes: notes.filter { !$0.isBlank },
            events: events,
            trips: trips,
            anniversaries: anniversaries,
            ledger: ledger,
            tasks: tasks
        )
    }

    func writeBackupFile(now: Date = Date()) throws -> URL {
        let data = try makeBackup(now: now).encoded()
        let day = LocalDate.today(in: timeZone, now: now)
        let url = FileManager.default.temporaryDirectory.appending(path: "Nook-Backup-\(day.isoString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Replaces notes, schedule and finance records with a backup's. Throws
    /// `NookBackup.ReadError` for files that are not Nook backups.
    func restoreBackup(_ data: Data) throws {
        let backup = try NookBackup.decode(data)
        try database.replaceAll(with: backup)
        reload()
        dataRevision += 1
        syncReminders()
    }

    #if DEBUG
    /// Fills an empty database with the demo content, for UI tests.
    func loadSampleData(_ sample: SampleData) {
        _ = write { database in
            try database.replaceAll(with: NookBackup(
                notes: sample.notes,
                events: sample.events,
                trips: sample.trips,
                anniversaries: sample.anniversaries,
                ledger: sample.ledger
            ))
        }
        reload()
    }
    #endif
}

extension AppStore {
    /// The store the app starts with: the database on this iPhone, or, for UI tests, an
    /// in-memory database with demo content.
    static func makeForLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppStore {
        #if DEBUG
        if arguments.contains("-uiTesting"), let database = try? AppDatabase.makeInMemory() {
            let suite = "nook.uitesting"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let store = AppStore(database: database, attachments: .makeTemporary(), defaults: defaults, vaultParameters: .testing)
            store.loadSampleData(SampleData.make())
            return store
        }
        #endif
        do {
            return AppStore(database: try AppDatabase.openDefault(), attachments: try AttachmentStore.makeDefault())
        } catch {
            guard let database = try? AppDatabase.makeInMemory() else {
                fatalError("SQLite is not available: \(error)")
            }
            return AppStore(database: database, attachments: .makeTemporary(), isTemporary: true)
        }
    }
}
