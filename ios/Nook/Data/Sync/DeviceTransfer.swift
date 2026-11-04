import Foundation
import Network
import CryptoKit
import Observation
import NookCore

struct TransferPairing: Codable, Sendable {
    var format = "nook.pairing"
    var version = 1
    var session: UUID
    var service: String
    var publicKey: Data
    var expiresAt: Date
    var code: String { "nook-transfer://pair/" + Base64URL.encode((try? NookJSON.makeEncoder().encode(self)) ?? Data()) }
    static func parse(_ text: String) throws -> TransferPairing {
        let prefix = "nook-transfer://pair/"
        guard text.hasPrefix(prefix), text.count < 4096, let data = Base64URL.decode(String(text.dropFirst(prefix.count))) else { throw SyncError.invalidHistory }
        let value = try NookJSON.makeDecoder().decode(Self.self, from: data)
        guard value.format == "nook.pairing", value.version == 1, value.publicKey.count == 32,
              value.service == "nook-" + value.session.uuidString.lowercased(), value.expiresAt > Date(),
              value.expiresAt.timeIntervalSinceNow <= 660 else { throw SyncError.invalidHistory }
        return value
    }
}
struct S3TransferSettings: Codable, Sendable {
    var configuration: S3Configuration
    var credentials: S3Credentials
    var rootKey: Data
    var state: SyncLocalState
}
private struct TransferHello: Codable {
    var session: UUID
    var publicKey: Data
}
private struct TransferMessage: Codable {
    var type: String
    var bytes: Data? = nil
    var size: Int64? = nil
}

@MainActor @Observable
final class DeviceTransfer {
    private(set) var phase = "idle"
    private(set) var pairingCode: String?
    private(set) var verificationCode: String?
    private(set) var progress: Double = 0
    private(set) var error: String?
    private(set) var staged: StagedArchive?
    var includeS3 = true
    private let store: AppStore
    private var receiver = true
    private var listener: NWListener?
    private var connection: NWConnection?
    private var pairing: TransferPairing?
    private var privateKey = Curve25519.KeyAgreement.PrivateKey()
    private var key: Data?
    private var sent: UInt64 = 0, received: UInt64 = 0
    private var approved = false, peerApproved = false, started = false
    private var running: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var incoming: URL?
    private var handle: FileHandle?
    private var expected: Int64 = 0, transferred: Int64 = 0
    private let queue = DispatchQueue(label: "com.nook.personal.transfer")
    private var generation = 0

    init(store: AppStore) { self.store = store }
    func receive() {
        cancel(); receiver = true; error = nil
        let ticket = generation
        do {
            privateKey = Curve25519.KeyAgreement.PrivateKey()
            let id = UUID()
            let pairing = TransferPairing(session: id, service: "nook-" + id.uuidString.lowercased(),
                publicKey: privateKey.publicKey.rawRepresentation, expiresAt: Date().addingTimeInterval(600))
            self.pairing = pairing
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: pairing.service, type: "_nook-transfer._tcp")
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == ticket, self.connection == nil, (self.pairing?.expiresAt ?? .distantPast) > Date() else { connection.cancel(); return }
                    self.connection = connection; self.attach(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == ticket else { return }
                    switch state {
                    case .ready: self.pairingCode = pairing.code; self.phase = "waiting"
                    case .failed(let failure): self.fail(failure)
                    default: break
                    }
                }
            }
            self.listener = listener; listener.start(queue: queue); phase = "starting"
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled, let self, self.key == nil else { return }
                self.fail(SyncError.invalidHistory)
            }
        } catch { fail(error) }
    }
    func connect(code: String) {
        cancel(); receiver = false; error = nil
        do {
            let pairing = try TransferPairing.parse(code); self.pairing = pairing
            privateKey = Curve25519.KeyAgreement.PrivateKey()
            let connection = NWConnection(to: .service(name: pairing.service, type: "_nook-transfer._tcp", domain: "local.", interface: nil), using: .tcp)
            self.connection = connection; phase = "connecting"; attach(connection)
        } catch { fail(error) }
    }
    private func attach(_ connection: NWConnection) {
        let ticket = generation
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == ticket else { return }
                switch state {
                case .ready:
                    self.running = Task { do { try await self.handshake(); try await self.readMessages() } catch { if !Task.isCancelled && self.generation == ticket && self.phase != "completed" { self.fail(error) } } }
                case .failed(let failure): self.fail(failure)
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }
    private func handshake() async throws {
        guard let pairing, pairing.expiresAt > Date() else { throw SyncError.invalidHistory }
        let peer: TransferHello
        if receiver {
            peer = try NookJSON.makeDecoder().decode(TransferHello.self, from: await readFrame())
            guard peer.session == pairing.session else { throw SyncError.invalidHistory }
            try await sendFrame(NookJSON.makeEncoder().encode(TransferHello(session: pairing.session, publicKey: privateKey.publicKey.rawRepresentation)))
        } else {
            try await sendFrame(NookJSON.makeEncoder().encode(TransferHello(session: pairing.session, publicKey: privateKey.publicKey.rawRepresentation)))
            peer = try NookJSON.makeDecoder().decode(TransferHello.self, from: await readFrame())
            guard peer.session == pairing.session, peer.publicKey == pairing.publicKey else { throw SyncError.invalidHistory }
        }
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer.publicKey))
        try Task.checkCancellation()
        let derived = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(pairing.session.uuidString.utf8),
                                                    sharedInfo: Data("nook.device-transfer.v1".utf8), outputByteCount: 32)
        key = derived.withUnsafeBytes { Data($0) }
        let sas = HMAC<SHA256>.authenticationCode(for: Data("compare-on-both-screens".utf8), using: derived)
        let number = Data(sas).prefix(3).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        verificationCode = String(format: "%06u", number); phase = "verify"; pairingCode = nil
        timeout?.cancel(); listener?.cancel(); listener = nil
    }
    func approve() {
        guard phase == "verify", !approved else { return }
        approved = true
        phase = "awaitingApproval"
        let ticket = generation
        Task {
            do { try await send(.init(type: "approve")); try await startIfReady() }
            catch { if generation == ticket { fail(error) } }
        }
    }
    private func startIfReady() async throws {
        guard approved && peerApproved, !started else { return }
        started = true
        let ticket = generation
        if receiver { phase = "receiving"; return }
        phase = "preparing"
        guard let key else { throw SyncError.invalidHistory }
        var values = try store.portableValues()
        if includeS3, let settings = try store.syncCoordinator.transferSettings(values: values) { values["migration/s3"] = try .from(settings) }
        let refs = try AppStore.attachmentRefs(in: values), folder = store.attachments.folder
        let file = try await Task.detached(priority: .userInitiated) { try BackupArchive.write(values: values, refs: refs, folder: folder, key: key) }.value
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard generation == ticket else { throw CancellationError() }
        let source = try FileHandle(forReadingFrom: file); defer { try? source.close() }
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard let size else { throw SyncError.invalidHistory }
        expected = size.int64Value; phase = "sending"
        try await send(.init(type: "begin", size: expected))
        var count: Int64 = 0
        while let bytes = try source.read(upToCount: 256 * 1024), !bytes.isEmpty {
            guard generation == ticket else { throw CancellationError() }
            try Task.checkCancellation(); try await send(.init(type: "chunk", bytes: bytes)); count += Int64(bytes.count)
            progress = Double(count) / Double(max(1, expected))
        }
        try await send(.init(type: "end")); phase = "awaitingImport"
    }
    private func readMessages() async throws {
        let ticket = generation
        while !Task.isCancelled {
            guard let key, let pairing else { throw SyncError.invalidHistory }
            let bytes = try await readFrame()
            try Task.checkCancellation()
            guard generation == ticket else { throw CancellationError() }
            let direction = receiver ? "sender" : "receiver"
            let clear = try SyncCrypto.open(bytes, key: key, context: "transfer/\(pairing.session)/\(direction)/\(received)")
            received += 1
            let message = try NookJSON.makeDecoder().decode(TransferMessage.self, from: clear)
            switch message.type {
            case "approve": peerApproved = true; try await startIfReady()
            case "begin":
                guard receiver, approved, peerApproved, incoming == nil, let size = message.size, size > 0, size <= 20 * 1024 * 1024 * 1024 else { throw SyncError.invalidHistory }
                let folder = FileManager.default.temporaryDirectory
                if let capacity = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
                   capacity < size + 100 * 1024 * 1024 { throw CocoaError(.fileWriteOutOfSpace) }
                let file = folder.appending(path: "Nook-Receiving-\(UUID()).nookbackup")
                guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw CocoaError(.fileWriteUnknown) }
                incoming = file; handle = try FileHandle(forWritingTo: file); expected = size; transferred = 0
            case "chunk":
                guard receiver, let handle, let data = message.bytes, data.count <= 256 * 1024,
                      transferred + Int64(data.count) <= expected else { throw SyncError.invalidHistory }
                try handle.write(contentsOf: data); transferred += Int64(data.count)
                progress = Double(transferred) / Double(max(1, expected))
            case "end":
                guard receiver, transferred == expected, let incoming else { throw SyncError.invalidHistory }
                try handle?.close(); handle = nil
                let decoded = try await Task.detached(priority: .userInitiated) { try BackupArchive.read(incoming, key: key) }.value
                guard generation == ticket else { try? FileManager.default.removeItem(at: decoded.folder); throw CancellationError() }
                staged = decoded
                phase = "readyToImport"
            case "complete": guard !receiver else { throw SyncError.invalidHistory }; phase = "completed"; return
            default: throw SyncError.invalidHistory
            }
        }
    }
    func install() {
        guard let staged, phase == "readyToImport" else { return }
        do {
            var clean = staged
            let settings = try clean.dataset.values.removeValue(forKey: "migration/s3")?.decoded(S3TransferSettings.self)
            if let settings { try SyncCrypto.validate(settings.state.library, key: settings.rootKey) }
            try BackupArchive.install(clean, into: store)
            if let settings { try store.installTransferredSync(settings) }
            phase = "completed"
            let ticket = generation
            Task {
                guard generation == ticket else { return }
                try? await send(.init(type: "complete"))
                if generation == ticket { connection?.cancel(); key = nil }
            }
            try? FileManager.default.removeItem(at: staged.folder); self.staged = nil
        } catch { self.error = error.localizedDescription }
    }
    private func send(_ message: TransferMessage) async throws {
        guard let key, let pairing else { throw SyncError.invalidHistory }
        let direction = receiver ? "receiver" : "sender", sequence = sent
        sent += 1
        let bytes = try SyncCrypto.seal(NookJSON.makeEncoder().encode(message), key: key,
                                        context: "transfer/\(pairing.session)/\(direction)/\(sequence)")
        try await sendFrame(bytes)
    }
    private func sendFrame(_ data: Data) async throws {
        guard let connection, data.count <= 1024 * 1024 else { throw SyncError.invalidHistory }
        var size = UInt32(data.count).bigEndian
        var bytes = withUnsafeBytes(of: &size) { Data($0) }; bytes.append(data)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: bytes, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
    private func readFrame() async throws -> Data {
        let size = try await exact(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= 1024 * 1024 else { throw SyncError.invalidHistory }
        return try await exact(Int(size))
    }
    private func exact(_ count: Int) async throws -> Data {
        guard let connection else { throw SyncError.invalidHistory }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, data.count == count { continuation.resume(returning: data) }
                else { continuation.resume(throwing: SyncError.invalidHistory) }
            }
        }
    }
    private func fail(_ failure: any Error) { error = failure.localizedDescription; phase = "failed"; connection?.cancel(); listener?.cancel(); timeout?.cancel() }
    func cancel() {
        generation += 1
        running?.cancel(); timeout?.cancel(); connection?.cancel(); listener?.cancel()
        running = nil; timeout = nil; connection = nil; listener = nil
        try? handle?.close(); handle = nil
        if let incoming { try? FileManager.default.removeItem(at: incoming) }; incoming = nil
        if let staged { try? FileManager.default.removeItem(at: staged.folder) }; staged = nil
        key = nil; pairing = nil; pairingCode = nil; verificationCode = nil
        sent = 0; received = 0; approved = false; peerApproved = false; started = false; progress = 0; phase = "idle"
    }
}
