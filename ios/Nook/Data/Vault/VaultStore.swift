import CryptoKit
import Foundation
import Observation
import NookCore

enum VaultError: Error {
    case locked
    case passwordTooShort
    case alreadyCreated
}

/// The vault's lock state and, while unlocked, its decrypted entries. Entries live in memory
/// only while unlocked; locking (or leaving the app) forgets them and the key.
@MainActor @Observable
final class VaultStore {
    enum State: Equatable {
        case needsSetup
        case locked
        case unlocked
    }

    private(set) var state: State
    private(set) var items: [VaultItem] = []
    /// Entries per category, known without unlocking.
    private(set) var counts: [VaultCategory: Int] = [:]
    /// Entries that could not be decrypted with the current key.
    private(set) var unreadableCount = 0
    private(set) var storageFailed = false

    /// Keep a Face ID copy of the vault key in the keychain.
    var usesQuickUnlock: Bool {
        didSet {
            defaults.set(usesQuickUnlock, forKey: Self.quickUnlockKey)
            if !usesQuickUnlock {
                keychain.delete()
            } else if let key {
                try? keychain.store(key)
            }
        }
    }

    @ObservationIgnored private var key: SymmetricKey?
    private let database: AppDatabase
    private let keychain: VaultKeychain
    private let defaults: UserDefaults
    private let parameters: VaultCrypto.KDFParameters
    @ObservationIgnored private var operation = 0
    private static let quickUnlockKey = "vault.quickUnlock"

    init(database: AppDatabase, keychain: VaultKeychain = VaultKeychain(), defaults: UserDefaults = .standard, parameters: VaultCrypto.KDFParameters = .standard) {
        self.database = database
        self.keychain = keychain
        self.defaults = defaults
        self.parameters = parameters
        usesQuickUnlock = defaults.object(forKey: Self.quickUnlockKey) as? Bool ?? true
        do {
            state = try database.vaultKey() == nil ? .needsSetup : .locked
        } catch {
            state = .locked
            storageFailed = true
        }
        keychain.deleteLegacyKey()
        reloadCounts()
        if state == .needsSetup && totalCount > 0 {
            state = .locked
            storageFailed = true
        }
    }

    var totalCount: Int { counts.values.reduce(0, +) }
    var categoryCount: Int { counts.filter { $0.value > 0 }.count }

    /// Whether Face ID (or the passcode) can open the vault right now.
    var canUnlockQuickly: Bool {
        state == .locked && !storageFailed && usesQuickUnlock && DeviceAuthentication.isAvailable && keychain.containsProtectedKey
    }

    func items(in category: VaultCategory?) -> [VaultItem] {
        let matching = category.map { category in items.filter { $0.category == category } } ?? items
        return matching.sorted(by: Self.displayOrder)
    }

    func item(id: UUID) -> VaultItem? {
        items.first { $0.id == id }
    }

    func search(_ text: String) -> [VaultItem] {
        items.filter { $0.matches(text) }.sorted(by: Self.displayOrder)
    }

    /// Favorites first, then by name.
    static func displayOrder(_ lhs: VaultItem, _ rhs: VaultItem) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    // MARK: - Locking

    /// Creates the vault, protected by a new master password.
    func setUp(masterPassword: String) async throws {
        guard masterPassword.count >= VaultCrypto.minimumPasswordLength else { throw VaultError.passwordTooShort }
        guard state == .needsSetup, try database.vaultKey() == nil else { throw VaultError.alreadyCreated }
        operation += 1
        let ticket = operation
        let parameters = self.parameters
        let vaultKey = VaultCrypto.makeVaultKey()
        let salt = VaultCrypto.makeSalt()
        let wrapped = try await Task.detached(priority: .userInitiated) {
            try VaultCrypto.wrap(vaultKey, with: VaultCrypto.deriveKey(password: masterPassword, salt: salt, parameters: parameters))
        }.value
        guard ticket == operation else { throw CancellationError() }
        let record = VaultKeyRecord(
            version: VaultCrypto.keyVersion,
            salt: salt,
            rounds: parameters.operations,
            memoryLimit: parameters.memoryBytes,
            wrappedKey: wrapped,
            keyCheck: try VaultCrypto.makeKeyCheck(vaultKey),
            createdAt: Date()
        )
        try database.save(record)
        state = .locked
        try open(with: vaultKey)
    }

    /// Throws `VaultCrypto.Failure.wrongPassword` for a wrong password.
    func unlock(masterPassword: String) async throws {
        operation += 1
        let ticket = operation
        guard let record = try database.vaultKey() else {
            guard try database.vaultRecords().isEmpty else { throw VaultCrypto.Failure.corrupted }
            state = .needsSetup
            return
        }
        let vaultKey = try await Task.detached(priority: .userInitiated) {
            try VaultCrypto.unwrap(record.wrappedKey, with: VaultCrypto.passwordKey(masterPassword, record: record), version: record.version)
        }.value
        guard ticket == operation else { throw CancellationError() }
        guard VaultCrypto.isKey(vaultKey, matching: record.keyCheck, version: record.version) else { throw VaultCrypto.Failure.corrupted }
        if record.version == 1 {
            try await upgradeLegacyVault(record, with: vaultKey, password: masterPassword, ticket: ticket)
        }
        guard ticket == operation else { throw CancellationError() }
        try open(with: vaultKey)
    }

    /// Face ID / passcode unlock with the keychain copy of the key. Returns false when that is
    /// not possible; the master password still works.
    func unlockQuickly() async -> Bool {
        guard canUnlockQuickly else { return false }
        operation += 1
        let ticket = operation
        let keychain = self.keychain
        let reason = String(localized: "Unlock your vault")
        let vaultKey = await Task.detached(priority: .userInitiated) { keychain.load(reason: reason) }.value
        guard ticket == operation, let vaultKey else { return false }
        do {
            guard let record = try database.vaultKey(), record.version == VaultCrypto.keyVersion,
                  VaultCrypto.isKey(vaultKey, matching: record.keyCheck, version: record.version) else {
                keychain.delete()
                return false
            }
            try open(with: vaultKey, rememberForQuickUnlock: false)
            return true
        } catch { return false }
    }

    func lock() {
        operation += 1
        key = nil
        items = []
        unreadableCount = 0
        if state == .unlocked {
            state = .locked
        }
    }

    func changeMasterPassword(current: String, new newPassword: String) async throws {
        guard state == .unlocked else { throw VaultError.locked }
        guard newPassword.count >= VaultCrypto.minimumPasswordLength else { throw VaultError.passwordTooShort }
        guard var record = try database.vaultKey() else { throw VaultError.locked }
        let old = record
        operation += 1
        let ticket = operation
        let parameters = self.parameters
        let salt = VaultCrypto.makeSalt()
        let wrapped = try await Task.detached(priority: .userInitiated) {
            let vaultKey = try VaultCrypto.unwrap(old.wrappedKey, with: VaultCrypto.passwordKey(current, record: old), version: old.version)
            return try VaultCrypto.wrap(vaultKey, with: VaultCrypto.deriveKey(password: newPassword, salt: salt, parameters: parameters))
        }.value
        guard ticket == operation, state == .unlocked else { throw CancellationError() }
        record.salt = salt
        record.rounds = parameters.operations
        record.memoryLimit = parameters.memoryBytes
        record.wrappedKey = wrapped
        try database.save(record)
    }

    /// Deletes every entry and the master password, for a forgotten password.
    func reset() throws {
        try database.eraseVault()
        operation += 1
        keychain.delete()
        key = nil
        items = []
        unreadableCount = 0
        counts = [:]
        storageFailed = false
        state = .needsSetup
    }

    private func open(with vaultKey: SymmetricKey, rememberForQuickUnlock: Bool = true) throws {
        var decrypted: [VaultItem] = []
        var failures = 0
        for record in try database.vaultRecords() {
            if let item = try? VaultCrypto.open(record.sealed, id: record.id, category: record.category, version: record.keyVersion, with: vaultKey) {
                decrypted.append(item)
            } else {
                failures += 1
            }
        }
        key = vaultKey
        items = decrypted
        unreadableCount = failures
        state = .unlocked
        storageFailed = false
        if usesQuickUnlock && rememberForQuickUnlock {
            try? keychain.store(vaultKey)
        }
    }

    private func upgradeLegacyVault(_ old: VaultKeyRecord, with vaultKey: SymmetricKey, password: String, ticket: Int) async throws {
        // Decode every row first. A damaged row aborts migration without overwriting anything.
        let upgraded = try database.vaultRecords().map { row in
            let item = try VaultCrypto.open(row.sealed, id: row.id, category: row.category, version: row.keyVersion, with: vaultKey)
            var row = row
            row.keyVersion = VaultCrypto.keyVersion
            row.sealed = try VaultCrypto.seal(item, with: vaultKey)
            return row
        }
        let parameters = self.parameters
        let salt = VaultCrypto.makeSalt()
        let wrapped = try await Task.detached(priority: .userInitiated) {
            try VaultCrypto.wrap(vaultKey, with: VaultCrypto.deriveKey(password: password, salt: salt, parameters: parameters))
        }.value
        guard ticket == operation else { throw CancellationError() }
        var record = old
        record.version = VaultCrypto.keyVersion
        record.salt = salt
        record.rounds = parameters.operations
        record.memoryLimit = parameters.memoryBytes
        record.wrappedKey = wrapped
        record.keyCheck = try VaultCrypto.makeKeyCheck(vaultKey)
        try database.replaceVault(key: record, records: upgraded)
    }

    private func reloadCounts() {
        do {
            let categories = try database.vaultCategories()
            counts = Dictionary(grouping: categories) { $0 }.mapValues(\.count)
        } catch {
            storageFailed = true
        }
    }

    // MARK: - Entries

    func save(_ item: VaultItem) throws {
        guard let key else { throw VaultError.locked }
        var saved = item
        let existing = items.firstIndex { $0.id == item.id }
        if let existing {
            guard items[existing] != item else { return }
            saved.updatedAt = Date()
        }
        let record = VaultRecord(
            id: saved.id,
            category: saved.category,
            keyVersion: VaultCrypto.keyVersion,
            sealed: try VaultCrypto.seal(saved, with: key),
            createdAt: saved.createdAt,
            updatedAt: saved.updatedAt
        )
        try database.save(record)
        if let existing {
            items[existing] = saved
        } else {
            items.append(saved)
        }
        reloadCounts()
    }

    func delete(_ id: UUID) throws {
        guard key != nil, state == .unlocked else { throw VaultError.locked }
        try database.delete(VaultRecord.self, id: id)
        items.removeAll { $0.id == id }
        reloadCounts()
    }
}
