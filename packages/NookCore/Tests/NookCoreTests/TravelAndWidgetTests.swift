import Foundation
import Testing
@testable import NookCore

struct TravelAndWidgetTests {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!
    private var day: LocalDate { LocalDate(isoString: "2026-11-05")! }

    @Test func tripAndJourneyUseOneTransactionAndPreserveExistingIDs() throws {
        let trip = TripPlan(title: "Hangzhou", startDate: day, endDate: day)
        let event = ScheduleEvent(title: "Train G123", start: day.date(hour: 8, in: zone), end: day.date(hour: 9, in: zone), reminderMinutes: 30,
                                  transport: .init(number: "G123", departure: "Shanghai", arrival: "Hangzhou", seat: "05A"))
        let plan = try TripJourneyPlan.make(trip: trip, previousTrip: nil, journey: event, previousJourney: nil)
        #expect(plan.mutations.count == 2)
        let saved = try #require(plan.mutations.last?.after).decoded(ScheduleEvent.self)
        #expect(saved.id == event.id && saved.planID == trip.id && saved.category == .travel)
        #expect(saved.transport?.seat == "05A")
        let reminders = ReminderPlan.make(events: [saved], tasks: [], anniversaries: [], now: day.date(hour: 7, in: zone), timeZone: zone)
        #expect(reminders.first?.fireDate == day.date(hour: 7, minute: 30, in: zone))
        let removing = try TripJourneyPlan.make(trip: trip, previousTrip: trip, journey: nil, previousJourney: saved)
        #expect(removing.mutations.last?.id == saved.id && removing.mutations.last?.after == nil)
    }
    @Test func legacyTransportCanJoinATripWithoutDuplicatingOrDiscardingIt() throws {
        let trip = TripPlan(title: "Trip", startDate: day, endDate: day)
        let legacy = ScheduleEvent(title: "Legacy", start: day.date(hour: 8, in: zone), notes: "Keep", transport: .init(number: "CA123", seat: "12A"))
        var changed = legacy; changed.transport?.seat = "12B"
        let plan = try TripJourneyPlan.make(trip: trip, previousTrip: nil, journey: changed, previousJourney: legacy)
        let saved = try #require(plan.mutations.last?.after).decoded(ScheduleEvent.self)
        #expect(saved.id == legacy.id && saved.notes == "Keep" && saved.transport?.number == "CA123")
        #expect(plan.mutations.last?.before == (try JSONValue.from(legacy)))
    }
    @Test func invalidArrivalAndBoardingCannotBeSaved() {
        let trip = TripPlan(title: "Trip", startDate: day, endDate: day)
        let start = day.date(hour: 8, in: zone)
        let event = ScheduleEvent(title: "Train", start: start, end: start.addingTimeInterval(-1), transport: .init())
        #expect(throws: (any Error).self) { try TripJourneyPlan.make(trip: trip, previousTrip: nil, journey: event, previousJourney: nil) }
        var boarding = event; boarding.end = start.addingTimeInterval(3600); boarding.transport?.boardingAt = start.addingTimeInterval(60)
        #expect(throws: (any Error).self) { try TripJourneyPlan.make(trip: trip, previousTrip: nil, journey: boarding, previousJourney: nil) }
    }
    @Test func widgetProjectionHasUsefulContentAndNeverExportsNoteBodies() throws {
        let now = day.date(hour: 7, in: zone)
        let note = Note(title: "Packing", body: "PRIVATE-NOTE-BODY", category: .travel)
        let trip = TripPlan(title: "Trip to Hangzhou", destination: "Hangzhou", startDate: day, endDate: day)
        let event = ScheduleEvent(title: "Train G123", start: day.date(hour: 8, in: zone), end: day.date(hour: 9, in: zone), planID: trip.id, transport: .init(number: "G123", seat: "PRIVATE-SEAT"))
        let anniversary = Anniversary(title: "Birthday", date: day)
        let hidden = WidgetSnapshot.make(notes: [note], events: [event], trips: [trip], tasks: [.init(title: "PRIVATE-TASK")], anniversaries: [anniversary], details: false, now: now, timeZone: zone)
        let hiddenJSON = try JSONValue.from(hidden).json
        #expect(!hiddenJSON.contains("PRIVATE") && !hiddenJSON.contains("Packing") && hidden.trip?.title == nil)
        #expect(hidden.agenda?.count == 1 && hidden.noteCount == 1 && hidden.openTaskCount == 1)
        let visible = WidgetSnapshot.make(notes: [note], events: [event], trips: [trip], tasks: [], anniversaries: [anniversary], details: true, now: now, timeZone: zone)
        #expect(visible.noteTitle == note.title && visible.trip?.route?.contains("G123") == true)
        #expect(!(try JSONValue.from(visible)).json.contains("PRIVATE-NOTE-BODY"))
        let untitled = Note(title: " \n ", body: "PRIVATE-UNTITLED-BODY", category: .personal)
        let untitledSnapshot = WidgetSnapshot.make(notes: [untitled], events: [], trips: [], tasks: [], anniversaries: [], details: true, now: now, timeZone: zone)
        #expect(untitledSnapshot.noteTitle == nil && untitledSnapshot.noteCount == 1)
        #expect(!(try JSONValue.from(untitledSnapshot)).json.contains("PRIVATE-UNTITLED-BODY"))
    }
    @Test func sharedDataDistinguishesPermissionEmptyCorruptAndSuccessfulReads() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nook-widget-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        if case .groupUnavailable = WidgetSharedData.read(directory: nil) {} else { Issue.record("Missing group was not diagnosed") }
        if case .awaitingData = WidgetSharedData.read(directory: folder) {} else { Issue.record("Empty group was not diagnosed") }
        let file = folder.appending(path: WidgetSnapshot.filename)
        try Data("corrupt".utf8).write(to: file)
        if case .unreadableData = WidgetSharedData.read(directory: folder) {} else { Issue.record("Invalid data was not diagnosed") }
        try NookJSON.makeEncoder().encode(WidgetSnapshot(openTaskCount: 2)).write(to: file, options: .atomic)
        #expect(WidgetSharedData.read(directory: folder).snapshot?.openTaskCount == 2)
    }
    @Test func oldWidgetSnapshotsStillDecode() throws {
        var legacy = try #require(JSONValue.from(WidgetSnapshot(openTaskCount: 3)).object)
        for key in ["agenda", "trip", "noteTitle", "noteCount", "timeZoneID"] { legacy.removeValue(forKey: key) }
        let snapshot = try JSONValue.object(legacy).decoded(WidgetSnapshot.self)
        #expect(snapshot.openTaskCount == 3 && snapshot.agenda == nil)
    }
    @Test func connectionTestsUseInferenceWithoutRecordsImagesOrTools() throws {
        for type in AIProtocol.allCases {
            let client = AIClient(configuration: .init(apiType: type, baseURL: type.defaultBase, model: "chosen-model"), apiKey: "test-only")
            let request = try client.makeConnectionTestRequest()
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(request.httpMethod == "POST" && request.timeoutInterval == 30)
            #expect(body["tools"] == nil && !body.json.contains("search_records") && body.json.contains("Reply OK."))
            #expect(request.url?.path.hasSuffix("models") == false)
            if type == .responses { #expect(body["store"] == .bool(false)) }
        }
        #expect(throws: AIError.self) { try AIClient(configuration: .init(model: "model"), apiKey: " ").makeConnectionTestRequest() }
    }
    @Test func assistantCanCreateAndUpdateTripTransportWithoutInventedIDs() throws {
        let transport = TransportDetails(number: "G123", departure: "Shanghai", arrival: "Hangzhou")
        let action = AgentAction(kind: .trip, operation: .create, fields: [
            "title": .string("Hangzhou"), "start_date": .string(day.isoString), "end_date": .string(day.isoString),
            "journey": .object(["start": .string(RFC3339.string(from: day.date(hour: 8, in: zone))), "transport": try .from(transport), "reminder_minutes": .integer(30)])
        ])
        let plan = try AgentPlanner.prepare([action], records: [], summary: "Trip", currency: "CNY")
        let trip = try #require(plan.mutations.first?.after).decoded(TripPlan.self)
        let event = try #require(plan.mutations.last?.after).decoded(ScheduleEvent.self)
        #expect(event.planID == trip.id && event.transport?.number == "G123")
        let records = try plan.mutations.map { AgentRecord(kind: $0.kind, id: $0.id, data: try #require($0.after)) }
        let update = AgentAction(kind: .trip, operation: .update, id: trip.id, fields: ["journey": .object(["transport": .object(["seat": .string("05A")])])])
        let changed = try AgentPlanner.prepare([update], records: records, summary: "Seat", currency: "CNY")
        let saved = try #require(changed.mutations.last?.after).decoded(ScheduleEvent.self)
        #expect(saved.id == event.id && saved.transport?.seat == "05A" && saved.transport?.number == "G123")
    }
}
