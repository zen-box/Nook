import Foundation

/// A vector clock detects concurrent edits without trusting either device's wall clock.
public struct SyncClock: Hashable, Codable, Sendable {
    public var counters: [String: UInt64]
    public init(_ counters: [String: UInt64] = [:]) { self.counters = counters }
    public func dominates(_ other: SyncClock) -> Bool {
        other.counters.allSatisfy { counters[$0.key, default: 0] >= $0.value }
            && counters.contains { $0.value > other.counters[$0.key, default: 0] }
    }
    public static func merged(_ clocks: [SyncClock]) -> SyncClock {
        var result: [String: UInt64] = [:]
        for clock in clocks { for (key, value) in clock.counters { result[key] = max(result[key, default: 0], value) } }
        return SyncClock(result)
    }
}
public struct SyncVersion: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var clock: SyncClock
    /// Nil is a deletion, retained so an offline device cannot resurrect it.
    public var payload: JSONValue?
    public var editedAt: Date
    public init(id: UUID = UUID(), clock: SyncClock, payload: JSONValue?, editedAt: Date = Date()) {
        self.id = id; self.clock = clock; self.payload = payload; self.editedAt = editedAt
    }
}
public struct SyncRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var heads: [SyncVersion]
    public init(id: String, heads: [SyncVersion]) { self.id = id; self.heads = heads }
    /// Concurrent deletion never silently hides an edited record. All heads remain recoverable.
    public var visible: SyncVersion? {
        heads.sorted {
            if ($0.payload != nil) != ($1.payload != nil) { return $0.payload != nil }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }
    public var hasConflict: Bool { heads.count > 1 }
    public mutating func merge(_ versions: [SyncVersion]) throws {
        var byID = Dictionary(uniqueKeysWithValues: heads.map { ($0.id, $0) })
        for version in versions {
            if let old = byID[version.id], old != version { throw SyncError.invalidHistory }
            byID[version.id] = version
        }
        let all = Array(byID.values)
        // Identical clocks with different contents indicate a broken writer, not an ordering.
        for a in all { for b in all where a.id != b.id && a.clock == b.clock {
            if a.payload != b.payload { throw SyncError.invalidHistory }
        } }
        heads = all.filter { value in !all.contains { $0.clock.dominates(value.clock) } }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
public struct SyncDocument: Hashable, Codable, Sendable {
    public var format = "nook.sync"
    public var version = 1
    public var libraryID: UUID
    public var records: [SyncRecord]
    public init(libraryID: UUID, records: [SyncRecord] = []) { self.libraryID = libraryID; self.records = records }
    public var conflicts: [SyncRecord] { records.filter(\.hasConflict) }
    public var materialized: [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: records.compactMap { record in record.visible?.payload.map { (record.id, $0) } })
    }
    public mutating func merge(_ other: SyncDocument) throws {
        guard format == "nook.sync", other.format == format, other.version == 1, version == 1,
              other.libraryID == libraryID else { throw SyncError.wrongLibrary }
        guard Set(other.records.map(\.id)).count == other.records.count else { throw SyncError.invalidHistory }
        for incoming in other.records {
            guard !incoming.heads.isEmpty else { throw SyncError.invalidHistory }
            if let index = records.firstIndex(where: { $0.id == incoming.id }) { try records[index].merge(incoming.heads) }
            else {
                var record = SyncRecord(id: incoming.id, heads: []); try record.merge(incoming.heads); records.append(record)
            }
        }
        records.sort { $0.id < $1.id }
    }
    /// Compare with the last locally applied projection, not with the just-downloaded remote.
    /// An edit based on one conflict head must not implicitly discard its siblings.
    public mutating func capture(_ values: [String: JSONValue], baseline: [String: JSONValue], deviceID: UUID, now: Date = Date()) throws {
        let device = deviceID.uuidString.lowercased()
        for key in Set(values.keys).union(baseline.keys).sorted() where values[key] != baseline[key] {
            let index = records.firstIndex { $0.id == key }
            let prior = index.map { records[$0] }
            let parent = prior?.heads.first { $0.payload == baseline[key] } ?? prior?.visible
            var clock = parent?.clock ?? SyncClock()
            // A device counter increases beyond every seen head, even when editing one branch.
            let greatest = prior?.heads.map { $0.clock.counters[device, default: 0] }.max() ?? 0
            guard greatest < UInt64.max else { throw SyncError.invalidHistory }
            clock.counters[device] = greatest + 1
            let change = SyncVersion(clock: clock, payload: values[key], editedAt: now)
            if let index { try records[index].merge([change]) }
            else { records.append(SyncRecord(id: key, heads: [change])) }
        }
        records.sort { $0.id < $1.id }
    }
    public mutating func resolve(recordID: String, choosing versionID: UUID, deviceID: UUID) throws {
        guard let index = records.firstIndex(where: { $0.id == recordID }),
              let selected = records[index].heads.first(where: { $0.id == versionID }) else { throw SyncError.invalidHistory }
        var clock = SyncClock.merged(records[index].heads.map(\.clock))
        let device = deviceID.uuidString.lowercased()
        guard clock.counters[device, default: 0] < UInt64.max else { throw SyncError.invalidHistory }
        clock.counters[device, default: 0] += 1
        records[index].heads = [SyncVersion(clock: clock, payload: selected.payload)]
    }
}
public enum SyncError: LocalizedError {
    case invalidHistory, wrongLibrary, missingAttachment, changedDuringSync, invalidRecoveryCode, notConfigured
    public var errorDescription: String? {
        switch self {
        case .invalidHistory: "The sync history is invalid. Your local data has not been replaced."
        case .wrongLibrary: "This data belongs to another library or an unsupported version."
        case .missingAttachment: "An attachment is missing or damaged. Sync has not been marked complete."
        case .changedDuringSync: "Local data changed during sync. Your changes are kept; sync again to finish."
        case .invalidRecoveryCode: "The recovery code could not decrypt this library."
        case .notConfigured: "Configure encrypted sync first."
        }
    }
}
