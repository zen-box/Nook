import Foundation
import CryptoKit
import Testing
import NookCore
@testable import Nook

@MainActor
struct SyncSafetyTests {
    private func store() throws -> AppStore {
        AppStore(database: try .makeInMemory(), attachments: .makeTemporary(), defaults: UserDefaults(suiteName: "nook.sync.tests.\(UUID())")!, vaultParameters: .testing)
    }
    @Test func encryptionAuthenticatesContextAndDetectsTampering() throws {
        let key = SyncCrypto.makeKey(), plain = Data("private data".utf8)
        let encrypted = try SyncCrypto.seal(plain, key: key, context: "file/a")
        #expect(try SyncCrypto.open(encrypted, key: key, context: "file/a") == plain)
        #expect(throws: (any Error).self) { try SyncCrypto.open(encrypted, key: key, context: "file/b") }
        #expect(throws: (any Error).self) { try SyncCrypto.open(encrypted, key: SyncCrypto.makeKey(), context: "file/a") }
        var damaged = encrypted; damaged[damaged.count - 1] ^= 1
        #expect(throws: (any Error).self) { try SyncCrypto.open(damaged, key: key, context: "file/a") }
        #expect(try SyncCrypto.key(from: SyncCrypto.code(key)) == key)
    }
    @Test func sealedVaultCommitsAdvanceSyncRevisionButUnlockingDoesNot() async throws {
        let store = try store()
        store.vault.usesQuickUnlock = false
        let initial = store.vault.syncRevision
        try await store.vault.setUp(masterPassword: "test-password-long-enough")
        #expect(store.vault.syncRevision == initial + 1)
        let item = VaultItem(title: "Secret", category: .account, icon: "lock", fields: [])
        try store.vault.save(item)
        #expect(store.vault.syncRevision == initial + 2)
        try store.vault.save(item)
        #expect(store.vault.syncRevision == initial + 2)
        store.vault.lock()
        try await store.vault.unlock(masterPassword: "test-password-long-enough")
        #expect(store.vault.syncRevision == initial + 2)
        try store.vault.delete(item.id)
        #expect(store.vault.syncRevision == initial + 3)
        try await store.vault.changeMasterPassword(current: "test-password-long-enough", new: "new-password-long-enough")
        #expect(store.vault.syncRevision == initial + 4)
        try store.vault.reset()
        #expect(store.vault.syncRevision == initial + 5)
    }
    @Test func encryptedArchiveRestoresPhotosAudioTasksAndSealedVault() async throws {
        let source = try store(), target = try store()
        defer { try? FileManager.default.removeItem(at: source.attachments.folder); try? FileManager.default.removeItem(at: target.attachments.folder) }
        let image = FileRef(name: "photo.jpg", kind: .image, byteCount: 3)
        let audio = FileRef(name: "voice.m4a", kind: .audio, byteCount: 4)
        try Data([1,2,3]).write(to: source.attachments.fileURL(for: image))
        try Data([4,5,6,7]).write(to: source.attachments.fileURL(for: audio))
        let note = Note(title: "Photo and recording", category: .personal, attachments: [image, audio])
        #expect(source.saveNote(note)); #expect(source.saveTask(.init(title: "Keep task")))
        source.vault.usesQuickUnlock = false
        try await source.vault.setUp(masterPassword: "original-vault-password")
        let item = VaultItem(title: "Private account", category: .account, icon: "lock", fields: [])
        try source.vault.save(item)
        let key = SyncCrypto.makeKey(), values = try source.portableValues()
        let archive = try BackupArchive.write(values: values, refs: [image,audio], folder: source.attachments.folder, key: key)
        defer { try? FileManager.default.removeItem(at: archive) }
        let staged = try BackupArchive.read(archive, key: key)
        defer { try? FileManager.default.removeItem(at: staged.folder) }
        try BackupArchive.install(staged, into: target)
        #expect(target.notes.first?.attachments.count == 2 && target.tasks.count == 1)
        #expect(try Data(contentsOf: target.attachments.fileURL(for: audio)) == Data([4,5,6,7]))
        #expect(target.vault.state == .locked)
        try await target.vault.unlock(masterPassword: "original-vault-password")
        #expect(target.vault.items.first?.title == item.title)
        #expect(throws: (any Error).self) { try BackupArchive.read(archive, key: SyncCrypto.makeKey()) }
    }
    @Test func missingAttachmentRejectsRestoreWithoutReplacingRecords() throws {
        let target = try store()
        #expect(target.saveNote(.init(title: "Keep", category: .personal)))
        let ref = FileRef(name: "missing.jpg", kind: .image, byteCount: 5)
        let note = Note(title: "Incoming", category: .personal, attachments: [ref])
        let dataset = PortableDataset(values: ["note/\(note.id)": try .from(note)], files: [])
        #expect(throws: (any Error).self) { try target.installPortable(dataset) }
        #expect(target.notes.map(\.title) == ["Keep"])
    }
    @Test func conflictingImmutableAttachmentRejectsArchiveWithoutTouchingExistingBytes() throws {
        let source = try store(), target = try store()
        defer { try? FileManager.default.removeItem(at: source.attachments.folder); try? FileManager.default.removeItem(at: target.attachments.folder) }
        let ref = FileRef(name: "photo.jpg", kind: .image, byteCount: 3)
        try Data([1,2,3]).write(to: source.attachments.fileURL(for: ref))
        try Data([4,5,6]).write(to: target.attachments.fileURL(for: ref))
        #expect(source.saveNote(.init(title: "Incoming", category: .personal, attachments: [ref])))
        #expect(target.saveNote(.init(title: "Keep", category: .personal, attachments: [ref])))
        let key = SyncCrypto.makeKey()
        let archive = try BackupArchive.write(values: source.portableValues(), refs: [ref], folder: source.attachments.folder, key: key)
        defer { try? FileManager.default.removeItem(at: archive) }
        let staged = try BackupArchive.read(archive, key: key)
        defer { try? FileManager.default.removeItem(at: staged.folder) }
        #expect(throws: SyncError.self) { try BackupArchive.install(staged, into: target) }
        #expect(target.notes.map(\.title) == ["Keep"])
        #expect(try Data(contentsOf: target.attachments.fileURL(for: ref)) == Data([4,5,6]))
    }
    @Test func expiredPairingIsRejectedAndCodeContainsNoLongTermSecret() throws {
        let id = UUID(), privateKey = Curve25519.KeyAgreement.PrivateKey()
        var pairing = TransferPairing(session: id, service: "nook-" + id.uuidString.lowercased(), publicKey: privateKey.publicKey.rawRepresentation, expiresAt: Date().addingTimeInterval(300))
        #expect(try TransferPairing.parse(pairing.code).session == id)
        #expect(!pairing.code.contains("NOOK1.") && !pairing.code.contains("secretKey"))
        pairing.expiresAt = Date().addingTimeInterval(-1)
        #expect(throws: (any Error).self) { try TransferPairing.parse(pairing.code) }
    }
    @Test func signaturePreservesPathEscapesAndSignsConditionalCreation() throws {
        let client = S3Client(configuration: S3Configuration(endpoint: "https://s3.example.com", bucket: "bucket", region: "us-east-1", prefix: "nook", pathStyle: true),
                              credentials: .init(accessKey: "test-access", secretKey: "test-secret"))
        let request = try client.signedRequest(method: "PUT", key: "nook/空 格+file", data: Data([1,2,3]), createOnly: true,
                                               now: Date(timeIntervalSince1970: 0))
        #expect(request.url?.absoluteString == "https://s3.example.com/bucket/nook/%E7%A9%BA%20%E6%A0%BC%2Bfile")
        #expect(request.value(forHTTPHeaderField: "x-amz-date") == "19700101T000000Z")
        #expect(request.value(forHTTPHeaderField: "if-none-match") == "*")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.contains("if-none-match") == true)
    }
}
