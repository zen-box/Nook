import Foundation
import GRDB
import Testing
import NookCore
@testable import Nook

@MainActor
struct AssistantSafetyTests {
    private func store(_ database: AppDatabase) -> AppStore {
        AppStore(database: database, attachments: .makeTemporary(), defaults: UserDefaults(suiteName: "nook.agent.tests.\(UUID())")!, vaultParameters: .testing)
    }
    @Test func confirmationIsAtomicAndReplayingCannotDuplicateRecords() throws {
        let db = try AppDatabase.makeInMemory(), store = store(db)
        let now = Date()
        let actions = [AgentAction(kind: .task, operation: .create, fields: ["title": .string("Task")]),
                       AgentAction(kind: .transaction, operation: .create, fields: ["title": .string("Lunch"), "amount_minor": .integer(2800), "occurred_at": .string(RFC3339.string(from: now))])]
        let plan = try AgentPlanner.prepare(actions, records: [], summary: "Add", currency: "CNY", now: now)
        #expect(store.tasks.isEmpty && store.ledger.isEmpty)
        try store.applyAssistantPlan(plan); try store.applyAssistantPlan(plan)
        #expect(store.tasks.count == 1 && store.ledger.count == 1)
        #expect(try db.loadSnapshot().tasks.count == 1)
    }
    @Test func laterConflictRollsBackEarlierWrites() throws {
        let db = try AppDatabase.makeInMemory(), store = store(db)
        var note = Note(title: "Old", body: "Keep", category: .work)
        #expect(store.saveNote(note))
        let plan = try AgentPlanner.prepare([
            .init(kind: .task, operation: .create, fields: ["title": .string("Must roll back")]),
            .init(kind: .note, operation: .update, id: note.id, fields: ["title": .string("AI edit")])
        ], records: store.assistantRecords(), summary: "Edit", currency: "CNY")
        note.title = "Edited elsewhere"; #expect(store.saveNote(note))
        #expect(throws: AgentPlanError.self) { try store.applyAssistantPlan(plan) }
        #expect(try db.loadSnapshot().tasks.isEmpty)
        #expect(store.note(id: note.id)?.title == "Edited elsewhere")
    }
    @Test func undoChangesTheExistingRecordAndChecksItsVersion() throws {
        let db = try AppDatabase.makeInMemory(), store = store(db)
        let note = Note(title: "Old", body: "Body", category: .personal)
        #expect(store.saveNote(note))
        let plan = try AgentPlanner.prepare([.init(kind: .note, operation: .update, id: note.id, fields: ["title": .string("New")])],
                                          records: store.assistantRecords(), summary: "Edit", currency: "CNY")
        try store.applyAssistantPlan(plan)
        let inverse = AgentPlan(summary: "Undo", mutations: plan.mutations.map { .init(kind: $0.kind, id: $0.id, before: $0.after, after: $0.before) })
        try store.applyAssistantPlan(inverse)
        #expect(store.notes.count == 1 && store.note(id: note.id)?.title == "Old")
    }
    @Test func assistantProjectionCannotContainVaultOrInfrastructureCredentials() async throws {
        let db = try AppDatabase.makeInMemory(), store = store(db)
        store.vault.usesQuickUnlock = false
        try await store.vault.setUp(masterPassword: "test-password-long-enough")
        let item = VaultItem(title: "PRIVATE-VAULT-TITLE", category: .account, icon: "lock", fields: [])
        try store.vault.save(item)
        store.defaults.set("PRIVATE-S3-KEY", forKey: "sync.key.test")
        #expect(store.assistantRecords().isEmpty)
        let text = try JSONValue.from(store.assistantRecords()).json
        #expect(!text.contains("PRIVATE") && !AgentTools.fieldGuide.contains("vault_item"))
    }
    @Test func recurringAndTransportFieldsSurviveDatabaseRestart() throws {
        let db = try AppDatabase.makeInMemory(), store = store(db)
        let start = Date(timeIntervalSince1970: 1_793_721_600)
        let event = ScheduleEvent(title: "Train", start: start, recurrence: .init(frequency: .weekly, weekdays: [1,3], timeZoneID: "Asia/Shanghai"),
                                  transport: .init(number: "G123", departure: "上海虹桥", arrival: "杭州东", carriage: "03", seat: "05A"))
        #expect(store.saveEvent(event))
        let reopened = self.store(db)
        #expect(reopened.events.first?.recurrence == event.recurrence)
        #expect(reopened.events.first?.transport?.departure == "上海虹桥")
        #expect(reopened.events.first?.transport?.seat == "05A")
    }
    @Test func tripTransportSavesTogetherAndAConflictRollsBackTheTrip() throws {
        let db = try AppDatabase.makeInMemory(), store = store(db)
        let day = LocalDate(isoString: "2026-11-05")!
        var trip = TripPlan(title: "Trip", startDate: day, endDate: day)
        let event = ScheduleEvent(title: "Train", start: day.date(hour: 8, in: .current), transport: .init(number: "G123"))
        let create = try TripJourneyPlan.make(trip: trip, previousTrip: nil, journey: event, previousJourney: nil)
        try store.applyAssistantPlan(create)
        let savedTrip = try #require(store.trip(id: trip.id)), savedEvent = try #require(store.event(id: event.id))
        #expect(savedEvent.planID == trip.id)
        trip = savedTrip; trip.title = "Must roll back"
        var changed = savedEvent; changed.transport?.seat = "05A"
        let plan = try TripJourneyPlan.make(trip: trip, previousTrip: savedTrip, journey: changed, previousJourney: savedEvent)
        var concurrent = savedEvent; concurrent.notes = "Edited elsewhere"
        #expect(store.saveEvent(concurrent))
        #expect(throws: AgentPlanError.self) { try store.applyAssistantPlan(plan) }
        #expect(try db.loadSnapshot().trips.first?.title == savedTrip.title)
        #expect(try db.loadSnapshot().events.first?.notes == "Edited elsewhere")
    }
    @Test func widgetLinksDismissSettingsAndOpenTheActualContent() throws {
        let store = store(try .makeInMemory()), router = AppRouter()
        var note = store.createNote(); note.title = "Recent"; #expect(store.saveNote(note))
        router.present(.settings)
        router.open(URL(string: "nook://notes")!, in: store)
        #expect(router.activeSheet == nil && router.selectedTab == .notes && router.notesPath == [.note(note.id)])
        router.present(.settings)
        router.open(URL(string: "nook://trips")!, in: store)
        #expect(router.activeSheet == nil && router.selectedTab == .schedule && router.scheduleSegment == .trips)
    }
}
