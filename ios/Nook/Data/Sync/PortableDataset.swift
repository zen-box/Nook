import Foundation
import GRDB
import NookCore

struct PortableVault: Codable, Sendable {
    var key: VaultKeyRecord?
    var records: [VaultRecord]
}
struct PortableFile: Codable, Hashable, Sendable {
    var ref: FileRef
    var bytes: Data
}
struct PortableDataset: Codable, Sendable {
    var format = "nook.transfer"
    var version = 1
    var values: [String: JSONValue]
    var files: [PortableFile]
}

extension AppStore {
    /// Infrastructure-only snapshot. Agent receives assistantRecords(), never this projection.
    func portableValues() throws -> [String: JSONValue] {
        var result = Dictionary(uniqueKeysWithValues: assistantRecords().map { ("\($0.kind.rawValue)/\($0.id)", $0.data) })
        let bundle = PortableVault(key: try database.vaultKey(), records: try database.vaultRecords())
        if bundle.key != nil || !bundle.records.isEmpty { result["vault/library"] = try .from(bundle) }
        var preferences: [String: JSONValue] = ["displayName": .string(displayName), "currency": .string(currencyCode),
            "budget": .integer(monthlyBudgetMinor), "appearance": .string(defaults.string(forKey: "appearance") ?? "system")]
        if let config = defaults.data(forKey: "ai.configuration"), let value = try? JSONDecoder().decode(JSONValue.self, from: config) { preferences["aiConfiguration"] = value }
        result["preferences/library"] = .object(preferences)
        return result
    }
    func portableDataset() throws -> PortableDataset {
        let values = try portableValues()
        let refs = try Self.attachmentRefs(in: values)
        let files = try refs.map { ref in
            let bytes = try Data(contentsOf: attachments.fileURL(for: ref))
            guard ref.byteCount.map({ $0 == bytes.count }) ?? true else { throw SyncError.missingAttachment }
            return PortableFile(ref: ref, bytes: bytes)
        }
        return PortableDataset(values: values, files: files)
    }
    static func attachmentRefs(in values: [String: JSONValue]) throws -> [FileRef] {
        var byID: [UUID: FileRef] = [:]
        for (key, value) in values where key.hasPrefix("note/") {
            for ref in try value.decoded(Note.self).attachments {
                if let old = byID[ref.id], old != ref { throw SyncError.missingAttachment }
                byID[ref.id] = ref
            }
        }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    /// Validate every file before installing any record. Content-address checks happen before here.
    func installPortable(_ dataset: PortableDataset, syncState: Data? = nil) throws {
        guard dataset.format == "nook.transfer", dataset.version == 1 else { throw SyncError.wrongLibrary }
        let previousValues = try portableValues()
        var backup = NookBackup(tasks: [])
        var vault: PortableVault?
        for (key, value) in dataset.values {
            if key == "vault/library" { vault = try value.decoded(PortableVault.self); continue }
            if key == "preferences/library" { continue }
            let components = key.split(separator: "/")
            guard components.count == 2, let kind = AgentRecordKind(rawValue: String(components[0])),
                  let id = UUID(uuidString: String(components[1])), value["id"]?.string.flatMap(UUID.init(uuidString:)) == id else { throw SyncError.invalidHistory }
            try AgentPlanner.validate(value, kind: kind)
            switch kind {
            case .note: backup.notes.append(try value.decoded(Note.self))
            case .event: backup.events.append(try value.decoded(ScheduleEvent.self))
            case .trip: backup.trips.append(try value.decoded(TripPlan.self))
            case .anniversary: backup.anniversaries.append(try value.decoded(Anniversary.self))
            case .transaction: backup.ledger.append(try value.decoded(LedgerEntry.self))
            case .task: backup.tasks?.append(try value.decoded(TaskItem.self))
            }
        }
        if let vault {
            guard Set(vault.records.map(\.id)).count == vault.records.count,
                  vault.key != nil || vault.records.isEmpty else { throw SyncError.invalidHistory }
        }
        let supplied = Dictionary(grouping: dataset.files, by: { $0.ref.id })
        for ref in try Self.attachmentRefs(in: dataset.values) {
            if let file = supplied[ref.id]?.first {
                guard file.ref == ref, ref.byteCount.map({ $0 == file.bytes.count }) ?? true else { throw SyncError.missingAttachment }
            } else {
                guard FileManager.default.fileExists(atPath: attachments.fileURL(for: ref).path) else { throw SyncError.missingAttachment }
            }
        }
        // Files are immutable UUIDs. Existing bytes must agree; failed DB commits only leave orphans.
        for file in dataset.files {
            let target = attachments.fileURL(for: file.ref)
            if FileManager.default.fileExists(atPath: target.path) {
                if try Data(contentsOf: target) != file.bytes {
                    let quarantine = attachments.folder.appending(path: "quarantine", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: target, to: quarantine.appending(path: "\(file.ref.id)-\(UUID()).damaged"))
                    try file.bytes.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
            } else { try file.bytes.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        }
        let previousVault = try JSONValue.from(PortableVault(key: database.vaultKey(), records: database.vaultRecords()))
        try database.writer.write { db in
            _ = try Note.deleteAll(db); _ = try ScheduleEvent.deleteAll(db); _ = try TripPlan.deleteAll(db)
            _ = try Anniversary.deleteAll(db); _ = try LedgerEntry.deleteAll(db); _ = try TaskItem.deleteAll(db)
            for n in backup.notes { try n.save(db) }; for e in backup.events { try e.save(db) }
            for t in backup.trips { try t.save(db) }; for a in backup.anniversaries { try a.save(db) }
            for e in backup.ledger { try e.save(db) }; for t in backup.tasks ?? [] { try t.save(db) }
            _ = try VaultRecord.deleteAll(db); _ = try VaultKeyRecord.deleteAll(db)
            if let key = vault?.key { try key.save(db) }
            for record in vault?.records ?? [] { try record.save(db) }
            if let syncState { try db.execute(sql: "INSERT OR REPLACE INTO app_metadata (key,value) VALUES ('sync.state',?)", arguments: [syncState]) }
        }
        if let p = dataset.values["preferences/library"] {
            displayName = p["displayName"]?.string ?? displayName
            currencyCode = p["currency"]?.string ?? currencyCode
            monthlyBudgetMinor = Int64(p["budget"]?.int ?? Int(monthlyBudgetMinor))
            if let a = p["appearance"]?.string, Appearance(rawValue: a) != nil { defaults.set(a, forKey: "appearance") }
            if let a = p["aiConfiguration"], let config = try? a.decoded(AIConfiguration.self) { defaults.set(try JSONEncoder().encode(config), forKey: "ai.configuration") }
        }
        if previousVault != dataset.values["vault/library"] { self.vault.reloadAfterImport() }
        if previousValues != dataset.values { didApplyRecords() }
    }
}
