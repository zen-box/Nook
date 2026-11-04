import CryptoKit
import Foundation
import GRDB
import Testing
import NookCore
@testable import Nook

private func hexData(_ text: String) -> Data {
    let bytes = Array(text.utf8)
    return Data(stride(from: 0, to: bytes.count, by: 2).map {
        UInt8(String(decoding: bytes[$0..<$0 + 2], as: UTF8.self), radix: 16)!
    })
}

/// Independently generated with PyNaCl/libsodium; see docs/local-vault.md.
struct VaultVectorTests {
    @Test func argon2idPreservesUnicodeAndEmbeddedNUL() throws {
        let key = try VaultCrypto.deriveKey(password: "主密码🔑\0Nook", salt: Data(0..<16), parameters: .testing)
        #expect(key.withUnsafeBytes { Data($0) } == hexData("7ed1a20b4cbad0cb1a94cd4b822d7654753ae9391b8cdf9bd2efdbcce922ac1b"))
    }

    @Test func xchachaMatchesIndependentCiphertext() throws {
        let sealed = hexData("000102030405060708090a0b0c0d0e0f1011121314151617d0ad6014b0372228d4e4a72b71c114c8adc846ea70e647ab84f639f991e0")
        let key = SymmetricKey(data: Data(0..<32))
        let aad = Data("nook-test-aad".utf8)
        #expect(try VaultCrypto.decrypt(sealed, with: key, aad: aad, version: 2) == Data("Nook 密码库".utf8))
        #expect(throws: (any Error).self) {
            try VaultCrypto.decrypt(sealed, with: key, aad: Data("other-type".utf8), version: 2)
        }
        var tampered = sealed
        tampered[tampered.count - 1] ^= 1
        #expect(throws: (any Error).self) { try VaultCrypto.decrypt(tampered, with: key, aad: aad, version: 2) }
        #expect(throws: (any Error).self) { try VaultCrypto.decrypt(Data(), with: key, aad: aad, version: 2) }
        #expect(throws: (any Error).self) { try VaultCrypto.decrypt(sealed, with: key, aad: aad, version: 99) }
    }

    @Test func sealingUsesFreshNoncesAndBindsRecordType() throws {
        let key = VaultCrypto.makeVaultKey()
        let item = VaultItem(title: "Mail", category: .account, icon: "envelope")
        let sealed = try VaultCrypto.seal(item, with: key)
        #expect(sealed != (try VaultCrypto.seal(item, with: key)))
        #expect(throws: (any Error).self) {
            try VaultCrypto.open(sealed, id: item.id, category: .card, version: 2, with: key)
        }
        let wrongType = Data("nook|\(item.id.uuidString.lowercased())|note|v2".utf8)
        #expect(throws: (any Error).self) { try VaultCrypto.decrypt(sealed, with: key, aad: wrongType, version: 2) }
    }

    @Test func invalidKDFParametersFailBeforeCallingC() {
        #expect(throws: (any Error).self) {
            try VaultCrypto.deriveKey(password: "password", salt: Data(), parameters: .testing)
        }
        #expect(throws: (any Error).self) {
            try VaultCrypto.deriveKey(password: "password", salt: Data(0..<16), parameters: .init(operations: -1, memoryBytes: Int.max))
        }
    }
}

@MainActor
struct VaultMigrationTests {
    private let password = "correct horse"

    private func vault(_ database: AppDatabase) -> VaultStore {
        let defaults = UserDefaults(suiteName: "nook.tests.\(UUID().uuidString)")!
        defaults.set(false, forKey: "vault.quickUnlock")
        return VaultStore(database: database, keychain: VaultKeychain(service: "nook.tests.\(UUID().uuidString)"), defaults: defaults, parameters: .testing)
    }

    private func seedLegacy(_ database: AppDatabase, damaged: Bool = false) throws -> VaultItem {
        let key = VaultCrypto.makeVaultKey()
        let salt = VaultCrypto.makeSalt()
        let passwordKey = try VaultCrypto.legacyKey(password: password, salt: salt, rounds: 1_000)
        let wrapped = try ChaChaPoly.seal(key.withUnsafeBytes { Data($0) }, using: passwordKey,
                                         authenticating: Data("nook.vault.key.v1".utf8)).combined
        let check = try ChaChaPoly.seal(Data("nook.vault.key-check.v1".utf8), using: key).combined
        try database.save(VaultKeyRecord(version: 1, salt: salt, rounds: 1_000, wrappedKey: wrapped, keyCheck: check, createdAt: Date()))
        // The persisted format has millisecond precision; use an exactly representable
        // fixture rather than comparing a nanosecond wall-clock value after JSON storage.
        let item = VaultItem(title: "Old account", category: .account, icon: "key",
                             fields: [VaultField(label: "Password", value: "old-secret", isSecret: true)],
                             createdAt: Date(timeIntervalSince1970: 1_793_786_130.125))
        var sealed = try ChaChaPoly.seal(NookJSON.makeEncoder().encode(item), using: key,
                                        authenticating: VaultCrypto.associatedData(id: item.id, version: 1)).combined
        if damaged { sealed[sealed.count - 1] ^= 1 }
        try database.save(VaultRecord(id: item.id, category: item.category, keyVersion: 1, sealed: sealed, createdAt: item.createdAt, updatedAt: item.updatedAt))
        return item
    }

    @Test func legacyRowsUpgradeAndReopen() async throws {
        let database = try AppDatabase.makeInMemory()
        let item = try seedLegacy(database)
        let store = vault(database)
        try await store.unlock(masterPassword: password)
        #expect(store.items == [item])
        let keyRecord = try #require(try database.vaultKey())
        #expect(keyRecord.version == 2)
        #expect(keyRecord.memoryLimit == VaultCrypto.KDFParameters.testing.memoryBytes)
        #expect(try database.vaultRecords().allSatisfy { $0.keyVersion == 2 })
        store.lock()
        let reopened = vault(database)
        try await reopened.unlock(masterPassword: password)
        #expect(reopened.items == [item])
    }

    @Test func damagedLegacyRowsAreNeverOverwritten() async throws {
        let database = try AppDatabase.makeInMemory()
        _ = try seedLegacy(database, damaged: true)
        let before = try #require(try database.vaultRecords().first)
        let store = vault(database)
        await #expect(throws: (any Error).self) { try await store.unlock(masterPassword: password) }
        #expect(store.state == .locked)
        #expect(try database.vaultKey()?.version == 1)
        #expect(try database.vaultRecords().first?.sealed == before.sealed)
    }

    @Test func lockingCancelsAnInFlightUnlock() async throws {
        let store = vault(try AppDatabase.makeInMemory())
        try await store.setUp(masterPassword: password)
        store.lock()
        // Runs on this actor when unlock suspends for its password derivation.
        let locking = Task { @MainActor in store.lock() }
        var cancelled = false
        do {
            try await store.unlock(masterPassword: password)
        } catch is CancellationError {
            cancelled = true
        }
        await locking.value
        #expect(cancelled)
        #expect(store.state == .locked)
        #expect(store.items.isEmpty)
    }

    @Test func lockedVaultCannotDeleteOrOverwriteItsKey() async throws {
        let database = try AppDatabase.makeInMemory()
        let store = vault(database)
        try await store.setUp(masterPassword: password)
        let before = try #require(try database.vaultKey())
        store.lock()
        #expect(throws: VaultError.self) { try store.delete(UUID()) }
        await #expect(throws: VaultError.self) { try await store.setUp(masterPassword: "replacement password") }
        #expect(try database.vaultKey()?.wrappedKey == before.wrappedKey)
    }
}
