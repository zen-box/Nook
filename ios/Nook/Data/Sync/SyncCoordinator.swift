import Foundation
import Observation
import CryptoKit
import NookCore

struct SyncAttachment: Hashable, Codable, Sendable {
    var ref: FileRef
    var objectKey: String
    var digest: String
}
struct SyncSnapshot: Codable, Sendable {
    var format = "nook.snapshot"
    var version = 1
    var createdAt = Date()
    var document: SyncDocument
    var attachments: [SyncAttachment]
}
struct SyncLocalState: Codable, Sendable {
    var library: SyncLibrary
    var document: SyncDocument
    var baseline: [String: JSONValue]
    var attachments: [SyncAttachment]
    var seen: [String]
    var history: [SyncHistoryItem]? = nil
    var configuration: S3Configuration? = nil
}
struct SyncHistoryItem: Identifiable, Codable, Sendable {
    var id: String
    var date: Date
}

@MainActor @Observable
final class SyncCoordinator {
    private(set) var isWorking = false
    private(set) var error: String?
    private(set) var status: String?
    private(set) var lastSuccess: Date?
    private(set) var conflicts: [SyncRecord] = []
    private(set) var history: [SyncHistoryItem] = []
    private var state: SyncLocalState?
    private let store: AppStore
    private let deviceID: UUID
    private var automaticSync: Task<Void, Never>?
    private let networkSession: URLSession?
    var configuration: S3Configuration? {
        return state?.configuration ?? store.defaults.data(forKey: "sync.configuration").flatMap { try? JSONDecoder().decode(S3Configuration.self, from: $0) }
    }
    init(store: AppStore, session: URLSession? = nil) {
        self.store = store
        networkSession = session
        if let id = store.defaults.string(forKey: "sync.deviceID").flatMap(UUID.init(uuidString:)) { deviceID = id }
        else { deviceID = UUID(); store.defaults.set(deviceID.uuidString, forKey: "sync.deviceID") }
        if let bytes = try? store.database.metadata("sync.state") { state = try? NookJSON.makeDecoder().decode(SyncLocalState.self, from: bytes) }
        conflicts = state?.document.conflicts ?? []
        history = state?.history ?? []
        lastSuccess = store.defaults.object(forKey: "sync.lastSuccess") as? Date
    }
    func configure(_ config: S3Configuration, credentials: S3Credentials, recovery: String?, create: Bool) async throws -> String? {
        guard !isWorking else { throw SyncError.changedDuringSync }
        isWorking = true; defer { isWorking = false }
        let client = S3Client(configuration: config, credentials: credentials, session: networkSession)
        let headerKey = client.path("library.json")
        let existing = try await client.get(headerKey)
        let library: SyncLibrary, key: Data
        if let existing {
            library = try NookJSON.makeDecoder().decode(SyncLibrary.self, from: existing)
            if let recovery, !recovery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { key = try SyncCrypto.key(from: recovery) }
            else if let stored = try SecretStore.read("sync.root.\(library.id)") { key = stored }
            else { throw SyncError.invalidRecoveryCode }
            try SyncCrypto.validate(library, key: key)
        } else {
            guard create, let recovery else { throw SyncError.notConfigured }
            key = try SyncCrypto.key(from: recovery)
            let id = UUID()
            library = SyncLibrary(id: id, keyCheck: try SyncCrypto.seal(Data("Nook library key check v1".utf8), key: key, context: "library/\(id)"))
            // Never replace an existing library, including when another device wins this race.
            try await client.put(NookJSON.makeEncoder().encode(library), key: headerKey, createOnly: true)
        }
        if let state, state.library.id != library.id { throw SyncError.wrongLibrary }
        try SecretStore.write(key, account: "sync.root.\(library.id)")
        let credentialAccount = try savedCredentialAccount()
        try SecretStore.write(JSONEncoder().encode(credentials), account: credentialAccount)
        store.defaults.set(try JSONEncoder().encode(config), forKey: "sync.configuration")
        if state == nil {
            var document = SyncDocument(libraryID: library.id)
            if create && existing == nil { try document.capture(store.portableValues(), baseline: [:], deviceID: deviceID) }
            state = SyncLocalState(library: library, document: document, baseline: [:], attachments: [], seen: [])
        }
        state?.configuration = config
        try persist()
        try Data().write(to: store.attachments.folder.appending(path: ".retain-sync-history"), options: .atomic)
        status = String(localized: "Connected. Sync now to upload or restore your library.")
        return existing == nil ? SyncCrypto.code(key) : nil
    }
    func recoveryCode() throws -> String {
        guard let state, let key = try SecretStore.read("sync.root.\(state.library.id)") else { throw SyncError.notConfigured }
        return SyncCrypto.code(key)
    }
    func transferSettings(values: [String: JSONValue]) throws -> S3TransferSettings? {
        guard configuration != nil else { return nil }
        let (client, key, saved) = try connection(); var copy = saved
        try copy.document.capture(values, baseline: copy.baseline, deviceID: deviceID)
        copy.baseline = values
        // The old phone must reserve every exported device counter too. Otherwise its
        // next offline edit could reuse a clock already carried to the new phone.
        state = copy; try persist()
        return .init(configuration: client.configuration, credentials: client.credentials, rootKey: key, state: copy)
    }
    private func connection() throws -> (S3Client, Data, SyncLocalState) {
        guard let state, let config = configuration, let encoded = try SecretStore.read(savedCredentialAccount()),
              let root = try SecretStore.read("sync.root.\(state.library.id)") else { throw SyncError.notConfigured }
        return (S3Client(configuration: config, credentials: try JSONDecoder().decode(S3Credentials.self, from: encoded), session: networkSession), root, state)
    }
    func savedCredentialAccount() throws -> String {
        if let bytes = try store.database.metadata("sync.credentials"), let name = String(data: bytes, encoding: .utf8), name.hasPrefix("sync.s3.") { return name }
        return "sync.s3"
    }
    func sync() async {
        guard !isWorking else { return }
        isWorking = true; error = nil; status = String(localized: "Synchronizing…")
        defer { isWorking = false }
        do {
            let (client, key, saved) = try connection()
            var current = saved
            var original = try store.portableValues()
            // A newly joined empty phone must not create a competing default settings record.
            if current.baseline.isEmpty && current.document.records.isEmpty && store.isEmpty && store.vault.totalCount == 0 { original.removeValue(forKey: "preferences/library") }
            try current.document.capture(original, baseline: current.baseline, deviceID: deviceID)
            // Persist generated operation clocks before uploading. A crash after PUT must not
            // reuse a device revision with different data on the next launch.
            state = current; try persist()
            let keys = try await client.list(prefix: client.path("snapshots/"))
            for object in keys where !current.seen.contains(object) {
                let snapshot = try await readSnapshot(object, client: client, key: key, libraryID: current.library.id)
                try current.document.merge(snapshot.document)
                try mergeAttachments(snapshot.attachments, into: &current.attachments)
                current.seen.append(object)
                current.history = (current.history ?? []) + [.init(id: object, date: snapshot.createdAt)]
            }
            // Do not overwrite edits made while requests were in flight.
            var latest = try store.portableValues()
            if original["preferences/library"] == nil && current.baseline.isEmpty && store.isEmpty && store.vault.totalCount == 0 { latest.removeValue(forKey: "preferences/library") }
            guard latest == original else { throw SyncError.changedDuringSync }
            let refs = try allRefs(current.document)
            for ref in refs where !current.attachments.contains(where: { $0.ref.id == ref.id }) {
                let data = try Data(contentsOf: store.attachments.fileURL(for: ref))
                guard ref.byteCount.map({ $0 == data.count }) ?? true else { throw SyncError.missingAttachment }
                let objectKey = client.path("files/\(UUID()).sealed")
                let bytes = try SyncCrypto.seal(data, key: key, context: "file/\(current.library.id)/\(ref.id)")
                try await client.put(bytes, key: objectKey, createOnly: true)
                current.attachments.append(.init(ref: ref, objectKey: objectKey, digest: S3Client.hex(SHA256.hash(data: data))))
            }
            let files = try await fetchFiles(refs, descriptors: current.attachments, client: client, key: key, library: current.library.id)
            let object = client.path("snapshots/\(UUID()).sealed")
            let snapshot = SyncSnapshot(document: current.document, attachments: current.attachments)
            let ciphertext = try SyncCrypto.seal(NookJSON.makeEncoder().encode(snapshot), key: key, context: "snapshot/\(current.library.id)/\(object)")
            // Attachments first, manifest last: an interrupted upload is never a committed snapshot.
            try await client.put(ciphertext, key: object, createOnly: true)
            var check = try store.portableValues()
            if original["preferences/library"] == nil && store.isEmpty && store.vault.totalCount == 0 { check.removeValue(forKey: "preferences/library") }
            guard check == original else { throw SyncError.changedDuringSync }
            current.seen.append(object); current.baseline = current.document.materialized
            current.history = (current.history ?? []) + [.init(id: object, date: snapshot.createdAt)]
            let dataset = PortableDataset(values: current.baseline, files: files)
            try store.installPortable(dataset, syncState: NookJSON.makeEncoder().encode(current))
            state = current; conflicts = current.document.conflicts
            lastSuccess = Date(); store.defaults.set(lastSuccess, forKey: "sync.lastSuccess")
            history = current.history ?? []
            status = conflicts.isEmpty ? String(localized: "All changes synchronized.") : String(localized: "Synchronized. Review the preserved conflicting versions.")
        } catch { self.error = error.localizedDescription; status = String(localized: "Sync incomplete. Local data is kept.") }
    }
    private func readSnapshot(_ object: String, client: S3Client, key: Data, libraryID: UUID) async throws -> SyncSnapshot {
        guard object.hasPrefix(client.path("snapshots/")), object.hasSuffix(".sealed"), let bytes = try await client.get(object) else { throw SyncError.invalidHistory }
        let clear = try SyncCrypto.open(bytes, key: key, context: "snapshot/\(libraryID)/\(object)")
        let snapshot = try NookJSON.makeDecoder().decode(SyncSnapshot.self, from: clear)
        guard snapshot.format == "nook.snapshot", snapshot.version == 1, snapshot.document.libraryID == libraryID else { throw SyncError.wrongLibrary }
        return snapshot
    }
    private func mergeAttachments(_ incoming: [SyncAttachment], into result: inout [SyncAttachment]) throws {
        for file in incoming {
            if let old = result.first(where: { $0.ref.id == file.ref.id }) {
                guard old.digest == file.digest, old.ref == file.ref else { throw SyncError.missingAttachment }
            } else { result.append(file) }
        }
    }
    private func allRefs(_ document: SyncDocument) throws -> [FileRef] {
        var all: [UUID: FileRef] = [:]
        for record in document.records where record.id.hasPrefix("note/") {
            for head in record.heads {
                if let payload = head.payload {
                    for ref in try payload.decoded(Note.self).attachments {
                        if let old = all[ref.id], old != ref { throw SyncError.missingAttachment }
                        all[ref.id] = ref
                    }
                }
            }
        }
        return Array(all.values)
    }
    private func fetchFiles(_ refs: [FileRef], descriptors: [SyncAttachment], client: S3Client, key: Data, library: UUID) async throws -> [PortableFile] {
        var files: [PortableFile] = []
        for ref in refs {
            guard let descriptor = descriptors.first(where: { $0.ref.id == ref.id }), descriptor.objectKey.hasPrefix(client.path("files/")) else { throw SyncError.missingAttachment }
            let local = try? Data(contentsOf: store.attachments.fileURL(for: ref))
            if let local, S3Client.hex(SHA256.hash(data: local)) == descriptor.digest { continue }
            guard let bytes = try await client.get(descriptor.objectKey) else { throw SyncError.missingAttachment }
            let clear = try SyncCrypto.open(bytes, key: key, context: "file/\(library)/\(ref.id)")
            guard S3Client.hex(SHA256.hash(data: clear)) == descriptor.digest else { throw SyncError.missingAttachment }
            files.append(.init(ref: ref, bytes: clear))
        }
        return files
    }
    func resolve(_ conflict: SyncRecord, choosing version: SyncVersion) async {
        guard !isWorking, var state else { return }
        do {
            // Refuse to resolve from a stale screen while local edits are pending.
            guard try store.portableValues() == state.baseline else { throw SyncError.changedDuringSync }
            try state.document.resolve(recordID: conflict.id, choosing: version.id, deviceID: deviceID)
            state.baseline = state.document.materialized
            try store.installPortable(.init(values: state.baseline, files: []), syncState: NookJSON.makeEncoder().encode(state))
            self.state = state; conflicts = state.document.conflicts
            await sync()
        } catch { self.error = error.localizedDescription }
    }
    func restoreHistory(_ item: SyncHistoryItem) async {
        guard !isWorking else { return }
        // Commit today's data as an encrypted history entry before restoring an older one.
        await sync()
        guard error == nil else { return }
        isWorking = true; defer { isWorking = false }
        do {
            let (client, key, saved) = try connection(); var current = saved
            let original = try store.portableValues()
            let snapshot = try await readSnapshot(item.id, client: client, key: key, libraryID: current.library.id)
            try mergeAttachments(snapshot.attachments, into: &current.attachments)
            try current.document.restore(snapshot.document.materialized, deviceID: deviceID)
            let refs = try allRefs(current.document)
            let files = try await fetchFiles(refs, descriptors: current.attachments, client: client, key: key, library: current.library.id)
            guard try store.portableValues() == original else { throw SyncError.changedDuringSync }
            current.baseline = current.document.materialized
            try store.installPortable(.init(values: current.baseline, files: files), syncState: NookJSON.makeEncoder().encode(current))
            state = current; conflicts = current.document.conflicts; status = String(localized: "History restored. Sync to propagate this restore to other devices.")
        } catch { self.error = error.localizedDescription }
    }
    func scheduleSync() {
        guard configuration != nil else { return }
        automaticSync?.cancel()
        automaticSync = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
                while self?.isWorking == true { try await Task.sleep(for: .seconds(1)) }
                guard let self, !Task.isCancelled else { return }
                await self.sync()
            } catch { }
        }
    }
    func disconnect() {
        guard !isWorking else { return }
        automaticSync?.cancel()
        state?.configuration = nil
        do { try persist() } catch { self.error = error.localizedDescription; return }
        store.defaults.removeObject(forKey: "sync.configuration")
        status = String(localized: "Disconnected. Local data and cloud history are kept.")
    }
    private func persist() throws {
        if let state { try store.database.setMetadata(NookJSON.makeEncoder().encode(state), key: "sync.state") }
    }
}
