import Foundation
import Testing
@testable import NookCore

struct AssistantAndSyncTests {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!
    private func date(_ day: String, _ hour: Int = 13) -> Date { LocalDate(isoString: day)!.date(hour: hour, in: zone) }

    @Test func weeklyMeetingUsesWeekdaysAndRespectsExceptions() {
        var rule = EventRecurrence(frequency: .weekly, weekdays: [1], timeZoneID: zone.identifier)
        let range = DateInterval(start: date("2026-11-01", 0), end: date("2026-12-01", 0))
        rule.excludedDates = [LocalDate(isoString: "2026-11-09")!]
        let dates = rule.starts(from: date("2026-11-02"), in: range)
        #expect(dates == [date("2026-11-02"), date("2026-11-16"), date("2026-11-23"), date("2026-11-30")])
    }
    @Test func monthlyClampsAndCountIncludesSkippedOccurrence() {
        let rule = EventRecurrence(frequency: .monthly, timeZoneID: zone.identifier, occurrenceLimit: 3,
                                   excludedDates: [LocalDate(isoString: "2027-02-28")!])
        let values = rule.starts(from: date("2027-01-31"), in: DateInterval(start: date("2027-01-01"), end: date("2027-06-01")))
        #expect(values == [date("2027-01-31"), date("2027-03-31")])
    }
    @Test func recurrenceKeepsLocalTimeAcrossDST() {
        let ny = TimeZone(identifier: "America/New_York")!
        let first = LocalDate(isoString: "2027-03-07")!.date(hour: 13, in: ny)
        let rule = EventRecurrence(frequency: .weekly, weekdays: [7], timeZoneID: ny.identifier, occurrenceLimit: 3)
        let dates = rule.starts(from: first, in: DateInterval(start: first, duration: 30 * 86400))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = ny
        #expect(dates.count == 3)
        #expect(dates.allSatisfy { calendar.component(.hour, from: $0) == 13 })
        #expect(dates[1].timeIntervalSince(dates[0]) == 7 * 86400 - 3600)
    }
    @Test func reminderPlanIncludesTasksAndAnniversaries() {
        let now = date("2026-11-04", 8)
        let task = TaskItem(title: "Task", dueAt: now.addingTimeInterval(3600), reminderMinutes: 10)
        let anniversary = Anniversary(title: "Birthday", date: LocalDate(isoString: "2000-11-05")!, reminder: .init(daysBefore: [0, 1]))
        let plan = ReminderPlan.make(events: [], tasks: [task], anniversaries: [anniversary], now: now, timeZone: zone)
        #expect(plan.contains { $0.id.hasPrefix("task-") })
        #expect(plan.filter { $0.title == "Birthday" }.count >= 2)
        #expect(plan.allSatisfy { $0.fireDate > now })
    }
    @Test func updatesPreserveUnrelatedFieldsAndRejectUnsupportedTargets() throws {
        let note = Note(title: "Original", body: "Body", category: .work, tags: ["keep"], isPinned: true)
        let record = AgentRecord(kind: .note, id: note.id, data: try .from(note))
        let plan = try AgentPlanner.prepare([.init(kind: .note, operation: .update, id: note.id, fields: ["title": .string("Changed")])],
                                          records: [record], summary: "Edit", currency: "CNY")
        let changed = try plan.mutations[0].after!.decoded(Note.self)
        #expect(changed.body == note.body && changed.tags == note.tags && changed.isPinned)
        #expect(throws: (any Error).self) { try AgentPlanner.prepare([.init(kind: .note, operation: .update, id: UUID())], records: [record], summary: "Edit", currency: "CNY") }
        #expect(AgentRecordKind(rawValue: "vault_item") == nil)
        #expect(throws: (any Error).self) { try AgentPlanner.prepare([.init(kind: .note, operation: .update, id: note.id, fields: ["password": .string("forbidden")])], records: [record], summary: "Edit", currency: "CNY") }
    }
    @Test func missingDatesAndInvalidAmountsAreRejected() {
        #expect(throws: (any Error).self) { try AgentPlanner.prepare([.init(kind: .event, operation: .create, fields: ["title": .string("No date")])], records: [], summary: "Add", currency: "CNY") }
        #expect(throws: (any Error).self) { try AgentPlanner.prepare([.init(kind: .transaction, operation: .create, fields: ["title": .string("Bad"), "amount_minor": .integer(-1), "occurred_at": .string(RFC3339.string(from: Date()))])], records: [], summary: "Add", currency: "CNY") }
    }
    @Test func singleOccurrenceEditCreatesOverrideAndExcludesOriginal() throws {
        let start = date("2026-11-02")
        let event = ScheduleEvent(title: "Meeting", start: start, recurrence: .init(frequency: .weekly, weekdays: [1], timeZoneID: zone.identifier))
        let occurrence = date("2026-11-09")
        let plan = try AgentPlanner.prepare([.init(kind: .event, operation: .update, id: event.id,
            fields: ["title": .string("Changed")], scope: "this", occurrenceStart: occurrence)],
            records: [.init(kind: .event, id: event.id, data: try .from(event))], summary: "Edit", currency: "CNY")
        #expect(plan.mutations.count == 2)
        let parent = try plan.mutations[0].after!.decoded(ScheduleEvent.self)
        let child = try plan.mutations[1].after!.decoded(ScheduleEvent.self)
        #expect(parent.recurrence?.excludedDates == [LocalDate(occurrence, timeZone: zone)])
        #expect(child.recurrence == nil && child.seriesID == event.id && child.start == occurrence)
    }
    @Test func concurrentEditsAndDeletionKeepBothBranchesAndConverge() throws {
        let library = UUID(), a = UUID(), b = UUID()
        var original = SyncDocument(libraryID: library)
        try original.capture(["note/1": .string("original")], baseline: [:], deviceID: a)
        var left = original, right = original
        try left.capture(["note/1": .string("edited")], baseline: original.materialized, deviceID: a)
        try right.capture([:], baseline: original.materialized, deviceID: b)
        var merged = left; try merged.merge(right)
        var reversed = right; try reversed.merge(left)
        #expect(merged == reversed)
        #expect(merged.conflicts.count == 1)
        #expect(merged.materialized["note/1"] == .string("edited"))
        try merged.resolve(recordID: "note/1", choosing: merged.records[0].heads.first { $0.payload == nil }!.id, deviceID: a)
        try merged.merge(left); try merged.merge(right)
        #expect(merged.conflicts.isEmpty && merged.materialized.isEmpty)
    }
    @Test func fourProtocolsEncodeNativeToolsAndParseReplies() throws {
        for type in AIProtocol.allCases {
            let config = AIConfiguration(apiType: type, baseURL: type.defaultBase, model: "test-model")
            let client = AIClient(configuration: config, apiKey: "test-key")
            let request = try client.makeRequest(system: "Nook", messages: [.init(role: "user", text: "Add task", images: [.init(data: Data([1,2,3]))])])
            #expect(request.url?.absoluteString.contains("/v1/v1/") == false)
            #expect(request.httpMethod == "POST")
            #expect(request.httpBody != nil)
            let raw: String
            switch type {
            case .chatCompletions: raw = #"{"choices":[{"message":{"tool_calls":[{"id":"c1","function":{"name":"ask_user","arguments":"{\"question\":\"Where?\",\"options\":[]}"}}]}}]}"#
            case .responses: raw = #"{"output":[{"type":"function_call","call_id":"c1","name":"ask_user","arguments":"{\"question\":\"Where?\",\"options\":[]}"}]}"#
            case .generateContent: raw = #"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"ask_user","args":{"question":"Where?","options":[]}}}]}}]}"#
            case .messages: raw = #"{"content":[{"type":"tool_use","id":"c1","name":"ask_user","input":{"question":"Where?","options":[]}}]}"#
            }
            let reply = try client.parse(JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)))
            #expect(reply.calls.count == 1 && reply.calls[0].name == "ask_user")
        }
    }
    @Test func oldRulesJumpToTheRequestedRangeWithoutRestartingTheirCount() {
        let origin = date("2000-01-03")
        let range = DateInterval(start: date("2036-11-01", 0), end: date("2036-11-08", 0))
        let weekly = EventRecurrence(frequency: .weekly, interval: 2, weekdays: [1, 3], timeZoneID: zone.identifier)
        let values = weekly.starts(from: origin, in: range)
        #expect(values == [date("2036-11-03"), date("2036-11-05")])
        var limited = weekly; limited.occurrenceLimit = 3
        #expect(limited.starts(from: origin, in: range).isEmpty)
        let monthly = EventRecurrence(frequency: .monthly, interval: 2, timeZoneID: zone.identifier)
        #expect(monthly.starts(from: date("2000-01-31"), in: DateInterval(start: date("2036-11-01", 0), end: date("2036-12-01", 0))) == [date("2036-11-30")])
    }
    @Test func allDayInstancesAndBoardingFollowTheirOwnOccurrence() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        let first = LocalDate(isoString: "2027-03-07")!.startDate(in: ny)
        let event = ScheduleEvent(title: "All day", start: first, end: first.addingTimeInterval(86400), isAllDay: true,
            recurrence: .init(frequency: .weekly, timeZoneID: ny.identifier), transport: .init(boardingAt: first.addingTimeInterval(-1800)))
        let target = LocalDate(isoString: "2027-03-14")!.startDate(in: ny)
        let instance = event.instance(starting: target)
        #expect(instance.end == LocalDate(isoString: "2027-03-15")!.startDate(in: ny))
        #expect(instance.transport?.boardingAt == target.addingTimeInterval(-1800))
        #expect(instance.displayID != event.displayID)
    }
    @Test func seriesOperationsIncludeOverridesAndDeletingUnlinksAreUndoable() throws {
        var root = ScheduleEvent(title: "Meeting", start: date("2026-11-02"), recurrence: .init(frequency: .weekly, timeZoneID: zone.identifier))
        root.recurrence?.excludedDates = [LocalDate(isoString: "2026-11-09")!]
        var child = root.instance(starting: date("2026-11-09"))
        child.id = UUID(); child.recurrence = nil; child.seriesID = root.id; child.title = "Custom"
        let records: [AgentRecord] = try [root,child].map { .init(kind: .event, id: $0.id, data: try .from($0)) }
        let deleted = try AgentPlanner.prepare([.init(kind: .event, operation: .delete, id: root.id, scope: "series")], records: records, summary: "Delete series", currency: "CNY")
        #expect(deleted.mutations.count == 2 && deleted.mutations.allSatisfy { $0.after == nil })
        let revised = try AgentPlanner.prepare([.init(kind: .event, operation: .update, id: root.id, fields: ["title": .string("Revised")], scope: "this", occurrenceStart: child.occurrenceStart)], records: records, summary: "Edit", currency: "CNY")
        #expect(revised.mutations.last?.id == child.id && revised.mutations.last?.before != nil)
        let future = try AgentPlanner.prepare([.init(kind: .event, operation: .update, id: root.id, fields: ["location": .string("Room A")], scope: "future", occurrenceStart: date("2026-11-09"))], records: records, summary: "Split", currency: "CNY")
        let replacement = try #require(future.mutations.first { $0.before == nil }?.after).decoded(ScheduleEvent.self)
        let reparented = try #require(future.mutations.first { $0.id == child.id }?.after).decoded(ScheduleEvent.self)
        #expect(reparented.seriesID == replacement.id && reparented.title == "Custom" && reparented.location == "Room A")
        let trip = TripPlan(title: "Trip", startDate: .today(), endDate: .today(), noteID: UUID())
        var linked = root; linked.planID = trip.id
        let unlink = try AgentPlanner.prepare([.init(kind: .trip, operation: .delete, id: trip.id)], records: [
            .init(kind: .trip, id: trip.id, data: try .from(trip)), .init(kind: .event, id: linked.id, data: try .from(linked))
        ], summary: "Remove trip", currency: "CNY")
        let change = try #require(unlink.mutations.first { $0.kind == .event })
        #expect(change.after?["plan_id"] == .null && change.before?["plan_id"] != .null)
    }
    @Test func syncVersionCanMergeWithItsPersistedCopyAndRestoreDominatesHistory() throws {
        var document = SyncDocument(libraryID: UUID())
        let device = UUID()
        try document.capture(["note/1": .string("Before")], baseline: [:], deviceID: device)
        let persisted = try NookJSON.makeDecoder().decode(SyncDocument.self, from: NookJSON.makeEncoder().encode(document))
        try document.merge(persisted)
        #expect(document.conflicts.isEmpty)
        var other = document
        try other.capture(["note/1": .string("After")], baseline: document.materialized, deviceID: UUID())
        try document.merge(other)
        try document.restore(["note/1": .string("Restored")], deviceID: device)
        try document.merge(other)
        #expect(document.materialized["note/1"] == .string("Restored") && document.conflicts.isEmpty)
    }
    @Test func millisecondEncodingRemainsStableAtFractionalBoundaries() throws {
        for seconds in [1_793_750_400.123, 1_793_750_400.9996, -0.001, 0.123, 1_793_750_400.500] {
            let encoded = RFC3339.string(from: Date(timeIntervalSince1970: seconds))
            let decoded = try #require(RFC3339.date(from: encoded))
            #expect(RFC3339.string(from: decoded) == encoded)
        }
    }
    @Test func parallelToolResultsStayTogetherAndProviderStateSurvives() throws {
        for type in [AIProtocol.generateContent, .messages] {
            let client = AIClient(configuration: .init(apiType: type, baseURL: type.defaultBase, model: "test"), apiKey: "fake")
            let part: JSONValue = .object(["functionCall": .object(["name": .string("ask_user"), "args": .object([:])]), "thoughtSignature": .string("opaque-provider-state")])
            let messages: [AIMessage] = [
                .init(role: "user", text: "Find"),
                .init(role: "assistant", calls: [.init(id: "c1", name: "search_records", arguments: .object([:]), providerPart: part), .init(id: "c2", name: "search_records", arguments: .object([:]))]),
                .init(role: "tool", text: "One", toolCallID: "c1", toolName: "search_records"),
                .init(role: "tool", text: "Two", toolCallID: "c2", toolName: "search_records")]
            let request = try client.makeRequest(system: "Nook", messages: messages)
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            let turns = try #require(body[type == .messages ? "messages" : "contents"]?.array)
            #expect(turns.count == 3)
            #expect(turns.last?[type == .messages ? "content" : "parts"]?.array?.count == 2)
            if type == .generateContent { #expect(turns[1]["parts"]?.array?.first?["thoughtSignature"]?.string == "opaque-provider-state") }
        }
    }
}
