import Foundation
import GRDB
import NookCore

extension AppDatabase {
    /// Receipt and every write commit together. Replaying a confirmed plan is a no-op.
    @discardableResult
    func applyAgentPlan(_ plan: AgentPlan) throws -> Bool {
        try writer.write { db in
            if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM agent_receipt WHERE id = ?)", arguments: [plan.id.uuidString]) == true { return false }
            for mutation in plan.mutations {
                let current = try Self.agentRecord(mutation.kind, id: mutation.id, db: db)
                guard current == mutation.before else { throw AgentPlanError.conflict }
                if let after = mutation.after {
                    try AgentPlanner.validate(after, kind: mutation.kind)
                    try Self.saveAgentRecord(after, kind: mutation.kind, db: db)
                } else {
                    switch mutation.kind {
                    case .note:
                        _ = try Note.deleteOne(db, key: mutation.id)
                    case .event: _ = try ScheduleEvent.deleteOne(db, key: mutation.id)
                    case .trip:
                        _ = try TripPlan.deleteOne(db, key: mutation.id)
                    case .anniversary: _ = try Anniversary.deleteOne(db, key: mutation.id)
                    case .transaction: _ = try LedgerEntry.deleteOne(db, key: mutation.id)
                    case .task: _ = try TaskItem.deleteOne(db, key: mutation.id)
                    }
                }
            }
            try db.execute(sql: "INSERT INTO agent_receipt (id, plan) VALUES (?, ?)", arguments: [plan.id.uuidString, try NookJSON.makeEncoder().encode(plan)])
            return true
        }
    }
    static func agentRecord(_ kind: AgentRecordKind, id: UUID, db: Database) throws -> JSONValue? {
        switch kind {
        case .note: try Note.fetchOne(db, key: id).map { try JSONValue.from($0) }
        case .event: try ScheduleEvent.fetchOne(db, key: id).map { try JSONValue.from($0) }
        case .trip: try TripPlan.fetchOne(db, key: id).map { try JSONValue.from($0) }
        case .anniversary: try Anniversary.fetchOne(db, key: id).map { try JSONValue.from($0) }
        case .transaction: try LedgerEntry.fetchOne(db, key: id).map { try JSONValue.from($0) }
        case .task: try TaskItem.fetchOne(db, key: id).map { try JSONValue.from($0) }
        }
    }
    static func saveAgentRecord(_ value: JSONValue, kind: AgentRecordKind, db: Database) throws {
        switch kind {
        case .note: try value.decoded(Note.self).save(db)
        case .event: try value.decoded(ScheduleEvent.self).save(db)
        case .trip: try value.decoded(TripPlan.self).save(db)
        case .anniversary: try value.decoded(Anniversary.self).save(db)
        case .transaction: try value.decoded(LedgerEntry.self).save(db)
        case .task: try value.decoded(TaskItem.self).save(db)
        }
    }
    func metadata(_ key: String) throws -> Data? {
        try writer.read { db in try Data.fetchOne(db, sql: "SELECT value FROM app_metadata WHERE key = ?", arguments: [key]) }
    }
    func setMetadata(_ value: Data, key: String) throws {
        try writer.write { db in try db.execute(sql: "INSERT OR REPLACE INTO app_metadata (key,value) VALUES (?,?)", arguments: [key, value]) }
    }
}
