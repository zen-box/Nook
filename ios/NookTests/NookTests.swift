import CryptoKit
import Foundation
import GRDB
import Testing
import NookCore
@testable import Nook

@MainActor
private func makeStore(_ database: AppDatabase) -> AppStore {
    AppStore(
        database: database,
        attachments: .makeTemporary(),
        defaults: UserDefaults(suiteName: "nook.tests.\(UUID().uuidString)")!,
        vaultParameters: .testing
    )
}

/// The demo data used by the UI tests reproduces the reference design's numbers.
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
        let recent = sample.notes.max { $0.updatedAt < $1.updatedAt }
        #expect(recent?.title == "Trip Plan – Japan")
    }
}

/// What is saved is still there when the app starts again (a new store on the same database).
@MainActor
struct PersistenceTests {
    @Test func migrationsAreApplied() throws {
        #expect(try AppDatabase.makeInMemory().appliedMigrations() == ["v1", "v2-vault-argon2id"])
    }

    @Test func recordsSurviveARestart() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nook-database-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "test.sqlite").path(percentEncoded: false)
        let writer = try DatabaseQueue(path: path)
        let database = try AppDatabase(writer)
        let store = makeStore(database)
        var note = store.createNote(category: .travel)
        note.title = "Packing"
        note.checklist = [ChecklistItem(text: "Passport", isDone: true)]
        note.tags = ["japan"]
        store.saveNote(note)
        let start = Date(timeIntervalSince1970: 1_793_721_600)
        store.saveEvent(ScheduleEvent(title: "Flight", start: start, end: start.addingTimeInterval(4 * 3600), location: "T2", category: .travel, reminderMinutes: 30))
        let trip = TripPlan(title: "Japan", startDate: LocalDate(year: 2026, month: 11, day: 4)!, endDate: LocalDate(year: 2026, month: 11, day: 10)!)
        store.saveTrip(trip)
        store.saveAnniversary(Anniversary(title: "Leap Day", date: LocalDate(year: 2000, month: 2, day: 29)!, kind: .birthday))
        store.saveEntry(LedgerEntry(amount: Money(minorUnits: 1_830, currencyCode: "CNY"), category: .food, title: "Coffee", occurredAt: start))

        try writer.close()
        let reopenedWriter = try DatabaseQueue(path: path)
        defer { try? reopenedWriter.close() }
        let reopened = makeStore(try AppDatabase(reopenedWriter))
        #expect(reopened.saveFailures == 0)
        #expect(reopened.notes.map(\.title) == ["Packing"])
        #expect(reopened.notes.first?.checklist.first?.isDone == true)
        #expect(reopened.notes.first?.tags == ["japan"])
        #expect(reopened.events.first?.start == start)
        #expect(reopened.events.first?.reminderMinutes == 30)
        #expect(reopened.events.first?.location == "T2")
        #expect(reopened.trips.first?.endDate == trip.endDate)
        #expect(reopened.anniversaries.first?.date == LocalDate(year: 2000, month: 2, day: 29))
        #expect(reopened.anniversaries.first?.kind == .birthday)
        #expect(reopened.ledger.first?.amountMinor == 1_830)
        #expect(reopened.ledger.first?.currencyCode == "CNY")
    }

    @Test func deletesAreStored() throws {
        let database = try AppDatabase.makeInMemory()
        let store = makeStore(database)
        let entry = LedgerEntry(amount: Money(minorUnits: 500, currencyCode: "USD"), category: .others, title: "Tip", occurredAt: Date())
        store.saveEntry(entry)
        store.deleteEntry(entry.id)
        #expect(makeStore(database).ledger.isEmpty)
    }

    @Test func blankNotesAreNeverStored() throws {
        let database = try AppDatabase.makeInMemory()
        let store = makeStore(database)
        let note = store.createNote()
        #expect(store.notes.count == 1)
        store.discardIfBlank(note.id)
        #expect(store.notes.isEmpty)
        #expect(makeStore(database).notes.isEmpty)
    }

    @Test func savingMovesTheEditTimeOnlyOnChanges() throws {
        let store = makeStore(try AppDatabase.makeInMemory())
        var note = store.createNote()
        note.title = "Ideas"
        store.saveNote(note)
        let saved = try #require(store.note(id: note.id))
        store.saveNote(saved)
        #expect(store.note(id: note.id)?.updatedAt == saved.updatedAt)
        var edited = saved
        edited.body = "More"
        store.saveNote(edited)
        #expect(try #require(store.note(id: note.id)).updatedAt >= saved.updatedAt)
        #expect(store.note(id: note.id)?.body == "More")
    }

    @Test func backupRestoresIntoAnEmptyDatabase() throws {
        let source = makeStore(try AppDatabase.makeInMemory())
        source.loadSampleData(SampleData.make())
        let data = try source.makeBackup().encoded()

        let target = makeStore(try AppDatabase.makeInMemory())
        try target.restoreBackup(data)
        #expect(Set(target.notes.map(\.id)) == Set(source.notes.map(\.id)))
        #expect(Set(target.events.map(\.id)) == Set(source.events.map(\.id)))
        #expect(target.ledger.count == source.ledger.count)
        #expect(target.trips.count == 1)
        #expect(throws: NookBackup.ReadError.self) {
            try target.restoreBackup(Data(#"{"hello":"world"}"#.utf8))
        }
    }

    @Test func togglingATodoUpdatesItsNote() throws {
        let store = makeStore(try AppDatabase.makeInMemory())
        store.loadSampleData(SampleData.make())
        let todo = try #require(store.openTodos(limit: 1).first)
        store.toggleChecklistItem(todo.item.id, in: todo.noteID)
        let item = store.note(id: todo.noteID)?.checklist.first { $0.id == todo.item.id }
        #expect(item?.isDone == true)
    }

    @Test func remindersOnlyCoverTimedEventsAhead() {
        let now = Date(timeIntervalSince1970: 1_793_721_600)
        let events = [
            ScheduleEvent(title: "Soon", start: now.addingTimeInterval(3600), reminderMinutes: 10),
            ScheduleEvent(title: "Past", start: now.addingTimeInterval(-3600), reminderMinutes: 10),
            ScheduleEvent(title: "Silent", start: now.addingTimeInterval(7200)),
            ScheduleEvent(title: "All day", start: now.addingTimeInterval(86_400), isAllDay: true, reminderMinutes: 0),
        ]
        let reminders = ReminderScheduler.upcoming(events, now: now)
        #expect(reminders.map { $0.event.title } == ["Soon"])
        #expect(reminders.first?.fireDate == now.addingTimeInterval(3000))
    }
}

/// The vault keeps entries only in encrypted form and needs the master password to read them.
@MainActor
struct VaultTests {
    private func makeVault(_ database: AppDatabase) -> VaultStore {
        VaultStore(
            database: database,
            keychain: VaultKeychain(service: "com.nook.personal.tests.\(UUID().uuidString)"),
            defaults: UserDefaults(suiteName: "nook.tests.\(UUID().uuidString)")!,
            parameters: .testing
        )
    }

    private let login = VaultItem(
        title: "Email",
        category: .account,
        icon: "envelope",
        fields: [
            VaultField(label: "Username", value: "alex@example.com"),
            VaultField(label: "Password", value: "s3cret-Passw0rd", isSecret: true),
        ]
    )

    @Test func itemsSurviveARestartEncrypted() async throws {
        let database = try AppDatabase.makeInMemory()
        let vault = makeVault(database)
        #expect(vault.state == .needsSetup)
        try await vault.setUp(masterPassword: "correct horse")
        try vault.save(login)
        #expect(vault.counts[.account] == 1)

        let stored = try #require(try database.vaultRecords().first)
        #expect(stored.category == .account)
        #expect(stored.sealed.range(of: Data("s3cret".utf8)) == nil)
        #expect(stored.sealed.range(of: Data("alex@example.com".utf8)) == nil)

        vault.lock()
        #expect(vault.items.isEmpty)
        let reopened = makeVault(database)
        #expect(reopened.state == .locked)
        #expect(reopened.totalCount == 1)
        try await reopened.unlock(masterPassword: "correct horse")
        #expect(reopened.items == [login])
        #expect(reopened.unreadableCount == 0)
    }

    @Test func wrongPasswordsAreRejected() async throws {
        let vault = makeVault(try AppDatabase.makeInMemory())
        try await vault.setUp(masterPassword: "correct horse")
        vault.lock()
        await #expect(throws: (any Error).self) {
            try await vault.unlock(masterPassword: "wrong horse")
        }
        #expect(vault.state == .locked)
        let fresh = makeVault(try AppDatabase.makeInMemory())
        await #expect(throws: VaultError.self) {
            try await fresh.setUp(masterPassword: "short")
        }
    }

    @Test func changingThePasswordKeepsTheItems() async throws {
        let database = try AppDatabase.makeInMemory()
        let vault = makeVault(database)
        try await vault.setUp(masterPassword: "first password")
        try vault.save(login)
        try await vault.changeMasterPassword(current: "first password", new: "second password")
        vault.lock()
        await #expect(throws: (any Error).self) {
            try await vault.unlock(masterPassword: "first password")
        }
        try await vault.unlock(masterPassword: "second password")
        #expect(vault.items == [login])
    }

    @Test func resetForgetsEverything() async throws {
        let database = try AppDatabase.makeInMemory()
        let vault = makeVault(database)
        try await vault.setUp(masterPassword: "correct horse")
        try vault.save(login)
        try vault.reset()
        #expect(vault.state == .needsSetup)
        #expect(vault.totalCount == 0)
        #expect(try database.vaultRecords().isEmpty)
    }

    @Test func sealedEntriesAreBoundToTheirRowAndKey() throws {
        let key = VaultCrypto.makeVaultKey()
        let sealed = try VaultCrypto.seal(login, with: key)
        #expect(try VaultCrypto.open(sealed, id: login.id, category: login.category, version: VaultCrypto.keyVersion, with: key) == login)
        #expect(throws: (any Error).self) {
            try VaultCrypto.open(sealed, id: UUID(), category: login.category, version: VaultCrypto.keyVersion, with: key)
        }
        #expect(throws: (any Error).self) {
            try VaultCrypto.open(sealed, id: login.id, category: login.category, version: VaultCrypto.keyVersion, with: VaultCrypto.makeVaultKey())
        }
    }

    /// PBKDF2-HMAC-SHA256 known answers for "password" / "salt".
    @Test(arguments: [
        (1, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"),
        (2, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"),
    ])
    func keyDerivationMatchesKnownAnswers(rounds: Int, expected: String) throws {
        let key = try VaultCrypto.legacyKey(password: "password", salt: Data("salt".utf8), rounds: rounds)
        let hex = key.withUnsafeBytes { bytes in bytes.map { String(format: "%02x", $0) }.joined() }
        #expect(hex == expected)
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

    @Test func newNotesOpenInTheNotesTab() throws {
        let router = AppRouter()
        let store = makeStore(try AppDatabase.makeInMemory())
        router.perform(.note, store: store)
        #expect(router.selectedTab == .notes)
        #expect(router.notesPath.count == 1)
    }

    @Test func addingAnAccountNeedsAnUnlockedVault() throws {
        let router = AppRouter()
        let store = makeStore(try AppDatabase.makeInMemory())
        router.perform(.account, store: store)
        #expect(router.selectedTab == .vault)
        #expect(router.activeSheet == nil)
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
