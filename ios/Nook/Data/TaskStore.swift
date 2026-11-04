import Foundation
import NookCore

extension AppStore {
    @discardableResult
    func saveTask(_ task: TaskItem) -> Bool {
        var saved = task; saved.updatedAt = Date()
        let record = AgentRecord(kind: .task, id: task.id, data: (try? .from(task)) ?? .null)
        let before = tasks.first { $0.id == task.id }.flatMap { try? JSONValue.from($0) }
        guard let after = try? JSONValue.from(saved) else { return false }
        do {
            try database.applyAgentPlan(AgentPlan(summary: task.title, mutations: [.init(kind: record.kind, id: task.id, before: before, after: after)]))
            didApplyRecords(); return true
        } catch { return false }
    }
    func deleteTask(_ id: UUID) throws {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        try database.applyAgentPlan(AgentPlan(summary: task.title, mutations: [.init(kind: .task, id: id, before: try .from(task), after: nil)]))
        didApplyRecords()
    }
    /// Only this explicitly typed projection crosses the Agent capability boundary.
    func assistantRecords() -> [AgentRecord] {
        func records<T: Identifiable & Encodable>(_ values: [T], _ kind: AgentRecordKind) -> [AgentRecord] where T.ID == UUID {
            values.compactMap { value in (try? JSONValue.from(value)).map { AgentRecord(kind: kind, id: value.id, data: $0) } }
        }
        return records(notes.filter { !$0.isBlank }, .note) + records(events, .event) + records(trips, .trip)
            + records(anniversaries, .anniversary) + records(ledger, .transaction) + records(tasks, .task)
    }
    func applyAssistantPlan(_ plan: AgentPlan) throws {
        try database.applyAgentPlan(plan)
        didApplyRecords()
    }
    func didApplyRecords() {
        reload(); dataRevision += 1; syncReminders()
    }
}
