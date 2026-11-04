import Foundation

/// Storage for one kind of record. The iOS app implements it on SQLite (GRDB) in P1; tests and
/// the P0 app use `InMemoryRepository`.
public protocol Repository<Record>: Sendable {
    associatedtype Record: Identifiable & Sendable where Record.ID == UUID

    /// Every record, in the order they were first stored.
    func all() async throws -> [Record]
    func record(id: UUID) async throws -> Record?
    /// Inserts the record, or replaces the stored one with the same id.
    func upsert(_ record: Record) async throws
    /// Removes the record with `id`. Deleting a missing record is not an error.
    func delete(id: UUID) async throws
}

/// A repository that keeps records in memory and loses them when released.
public actor InMemoryRepository<Record: Identifiable & Sendable>: Repository where Record.ID == UUID {
    private var records: [UUID: Record]
    private var order: [UUID]

    public init(_ initial: [Record] = []) {
        var records: [UUID: Record] = [:]
        var order: [UUID] = []
        for record in initial where records.updateValue(record, forKey: record.id) == nil {
            order.append(record.id)
        }
        self.records = records
        self.order = order
    }

    public var count: Int {
        records.count
    }

    public func all() -> [Record] {
        order.compactMap { records[$0] }
    }

    public func record(id: UUID) -> Record? {
        records[id]
    }

    public func upsert(_ record: Record) {
        if records.updateValue(record, forKey: record.id) == nil {
            order.append(record.id)
        }
    }

    public func delete(id: UUID) {
        if records.removeValue(forKey: id) != nil {
            order.removeAll { $0 == id }
        }
    }
}
