import Foundation
import GRDB
import NookCore

/// The app's SQLite database (GRDB). One table per record type; nested values such as
/// checklists are stored as JSON text. Vault entries are stored encrypted (`vault_record`).
final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// `Application Support/Database/nook.sqlite`, created on first launch.
    static func openDefault() throws -> AppDatabase {
        let fileManager = FileManager.default
        let folder = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Database", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: folder.path(percentEncoded: false)
        )
        let queue = try DatabaseQueue(path: folder.appending(path: "nook.sqlite").path(percentEncoded: false))
        return try AppDatabase(queue)
    }

    /// An empty database that lives only in memory, for tests.
    static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    /// Names of the migrations applied so far.
    func appliedMigrations() throws -> Set<String> {
        try writer.read { db in
            try Self.migrator.appliedIdentifiers(db)
        }
    }

    /// Schema changes are added as new migrations; existing ones never change.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "note") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("category", .text).notNull()
                t.column("tags", .text).notNull()
                t.column("pinned", .boolean).notNull()
                t.column("todos", .text).notNull()
                t.column("file_refs", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "event") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull()
                t.column("start", .datetime).notNull().indexed()
                t.column("end", .datetime)
                t.column("all_day", .boolean).notNull()
                t.column("location", .text)
                t.column("notes", .text).notNull()
                t.column("category", .text).notNull()
                t.column("reminder_minutes", .integer)
                t.column("plan_id", .blob)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "trip") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull()
                t.column("destination", .text)
                t.column("start_date", .text).notNull()
                t.column("end_date", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("note_id", .blob)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "anniversary") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull()
                t.column("date", .text).notNull()
                t.column("repeat_rule", .text).notNull()
                t.column("category", .text).notNull()
                t.column("description", .text).notNull()
                t.column("show_countdown", .boolean).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "ledger_entry") { t in
                t.primaryKey("id", .blob)
                t.column("type", .text).notNull()
                t.column("amount_minor", .integer).notNull()
                t.column("currency", .text).notNull()
                t.column("category", .text).notNull()
                t.column("title", .text).notNull()
                t.column("note", .text).notNull()
                t.column("occurred_at", .datetime).notNull().indexed()
                t.column("account_id", .blob)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "vault_record") { t in
                t.primaryKey("id", .blob)
                t.column("category", .text).notNull()
                t.column("key_version", .integer).notNull()
                t.column("sealed", .blob).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "vault_key") { t in
                t.primaryKey("id", .integer)
                t.column("version", .integer).notNull()
                t.column("salt", .blob).notNull()
                t.column("rounds", .integer).notNull()
                t.column("wrapped_key", .blob).notNull()
                t.column("key_check", .blob).notNull()
                t.column("created_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2-vault-argon2id") { db in
            try db.alter(table: "vault_key") { t in
                t.add(column: "memory_limit", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("v3-note-content") { db in
            try db.alter(table: "note") { t in
                t.add(column: "rich_content", .text)
            }
        }
        migrator.registerMigration("v4-assistant-schedule") { db in
            try db.alter(table: "event") { t in
                t.add(column: "recurrence", .text)
                t.add(column: "transport", .text)
                t.add(column: "series_id", .blob)
                t.add(column: "occurrence_start", .datetime)
            }
            try db.alter(table: "anniversary") { t in t.add(column: "reminder", .text) }
            try db.create(table: "task_item") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull()
                t.column("notes", .text).notNull()
                t.column("dueAt", .datetime)
                t.column("reminderMinutes", .integer)
                t.column("isCompleted", .boolean).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "agent_receipt") { t in
                t.primaryKey("id", .text)
                t.column("plan", .blob).notNull()
            }
            try db.create(table: "app_metadata") { t in
                t.primaryKey("key", .text)
                t.column("value", .blob).notNull()
            }
        }
        return migrator
    }
}

// MARK: - Reading and writing

/// Everything the screens show, read once at launch.
struct DatabaseSnapshot: Sendable {
    var notes: [Note] = []
    var events: [ScheduleEvent] = []
    var trips: [TripPlan] = []
    var anniversaries: [Anniversary] = []
    var ledger: [LedgerEntry] = []
    var tasks: [TaskItem] = []
}

extension AppDatabase {
    func loadSnapshot() throws -> DatabaseSnapshot {
        try writer.read { db in
            DatabaseSnapshot(
                notes: try Note.fetchAll(db),
                events: try ScheduleEvent.fetchAll(db),
                trips: try TripPlan.fetchAll(db),
                anniversaries: try Anniversary.fetchAll(db),
                ledger: try LedgerEntry.fetchAll(db),
                tasks: try TaskItem.fetchAll(db)
            )
        }
    }

    /// Inserts the record, or replaces the stored one with the same id.
    func save<Record: PersistableRecord & Sendable>(_ record: Record) throws {
        try writer.write { db in
            try record.save(db)
        }
    }

    func delete<Record: TableRecord>(_ type: Record.Type, id: UUID) throws {
        try writer.write { db in
            _ = try type.deleteOne(db, key: id)
        }
    }

    func savePlanNote(_ note: Note, trip: TripPlan) throws {
        try writer.write { db in
            try note.save(db)
            try trip.save(db)
        }
    }

    func deleteNote(_ id: UUID, updatedAt: Date) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE trip SET note_id = NULL, updated_at = ? WHERE note_id = ?", arguments: [updatedAt, id])
            _ = try Note.deleteOne(db, key: id)
        }
    }

    func deleteTrip(_ id: UUID, updatedAt: Date) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE event SET plan_id = NULL, updated_at = ? WHERE plan_id = ?", arguments: [updatedAt, id])
            _ = try TripPlan.deleteOne(db, key: id)
        }
    }

    /// Replaces notes, schedule and finance records with the backup's, in one transaction.
    /// The vault is not part of backups and stays as it is.
    func replaceAll(with backup: NookBackup) throws {
        try writer.write { db in
            _ = try Note.deleteAll(db)
            _ = try ScheduleEvent.deleteAll(db)
            _ = try TripPlan.deleteAll(db)
            _ = try Anniversary.deleteAll(db)
            _ = try LedgerEntry.deleteAll(db)
            _ = try TaskItem.deleteAll(db)
            for note in backup.notes { try note.save(db) }
            for event in backup.events { try event.save(db) }
            for trip in backup.trips { try trip.save(db) }
            for anniversary in backup.anniversaries { try anniversary.save(db) }
            for entry in backup.ledger { try entry.save(db) }
            for task in backup.tasks ?? [] { try task.save(db) }
        }
    }

    // MARK: Vault

    func vaultKey() throws -> VaultKeyRecord? {
        try writer.read { db in
            try VaultKeyRecord.fetchOne(db)
        }
    }

    func vaultRecords() throws -> [VaultRecord] {
        try writer.read { db in
            try VaultRecord.fetchAll(db)
        }
    }

    func vaultCategories() throws -> [VaultCategory] {
        try writer.read { db in
            try VaultCategory.fetchAll(db, sql: "SELECT category FROM vault_record")
        }
    }

    /// Upgrade ciphertext and its wrapped key atomically; rollback keeps v1 readable.
    func replaceVault(key: VaultKeyRecord, records: [VaultRecord]) throws {
        try writer.write { db in
            for record in records { try record.save(db) }
            try key.save(db)
        }
    }

    /// Removes every vault entry and the vault key.
    func eraseVault() throws {
        try writer.write { db in
            _ = try VaultRecord.deleteAll(db)
            _ = try VaultKeyRecord.deleteAll(db)
        }
    }
}

// MARK: - Records

/// One encrypted vault entry. Only the category is readable without the vault key, so the home
/// screen can count entries while the vault is locked.
struct VaultRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "vault_record"

    var id: UUID
    var category: VaultCategory
    var keyVersion: Int
    var sealed: Data
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case keyVersion = "key_version"
        case sealed
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The vault key, encrypted with a key derived from the master password.
struct VaultKeyRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "vault_key"

    var id: Int = 1
    var version: Int
    var salt: Data
    var rounds: Int
    var memoryLimit: Int = 0
    var wrappedKey: Data
    /// A known value sealed with the vault key, to tell a stale Face ID copy of the key apart.
    var keyCheck: Data
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case version
        case salt
        case rounds
        case memoryLimit = "memory_limit"
        case wrappedKey = "wrapped_key"
        case keyCheck = "key_check"
        case createdAt = "created_at"
    }
}

extension Note: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "note" }
}

extension ScheduleEvent: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "event" }
}

extension TripPlan: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "trip" }
}

extension Anniversary: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "anniversary" }
}

extension LedgerEntry: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "ledger_entry" }
}

extension TaskItem: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "task_item" }
}

// Columns hold the raw values of these enums and ISO dates for `LocalDate`.
extension NoteCategory: @retroactive DatabaseValueConvertible {}
extension EventCategory: @retroactive DatabaseValueConvertible {}
extension AnniversaryKind: @retroactive DatabaseValueConvertible {}
extension RepeatRule: @retroactive DatabaseValueConvertible {}
extension LedgerKind: @retroactive DatabaseValueConvertible {}
extension LedgerCategory: @retroactive DatabaseValueConvertible {}
extension VaultCategory: @retroactive DatabaseValueConvertible {}

extension LocalDate: @retroactive DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        isoString.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> LocalDate? {
        String.fromDatabaseValue(dbValue).flatMap { LocalDate(isoString: $0) }
    }
}
