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
}
