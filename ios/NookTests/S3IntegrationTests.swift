import Foundation
import Testing
import NookCore
@testable import Nook

/// In-memory HTTP transport exercises the production signer, encryption, manifests and
/// database import together. It never contacts a provider or uses real credentials.
@MainActor
struct S3IntegrationTests {
    private func store() throws -> AppStore {
        AppStore(database: try .makeInMemory(), attachments: .makeTemporary(), defaults: UserDefaults(suiteName: "nook.http.tests.\(UUID())")!, vaultParameters: .testing)
    }

    @Test func twoDevicesConvergePreserveConflictsAndRecoverAfterInterruptedUpload() async throws {
        let transport = MemoryS3(), a = try store(), b = try store()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MemoryS3Protocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let host = "\(UUID().uuidString.lowercased()).test.invalid"
        MemoryS3Protocol.register(transport, host: host)
        defer {
            MemoryS3Protocol.unregister(host: host); session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: a.attachments.folder)
            try? FileManager.default.removeItem(at: b.attachments.folder)
        }
        let config = S3Configuration(endpoint: "https://\(host)", bucket: "test", region: "us-east-1", prefix: "nook")
        let credentials = S3Credentials(accessKey: "FAKE-ACCESS", secretKey: "FAKE-SECRET")
        let code = SyncCrypto.code(SyncCrypto.makeKey())
        let left = SyncCoordinator(store: a, session: session), right = SyncCoordinator(store: b, session: session)
        let ref = FileRef(name: "voice.m4a", kind: .audio, byteCount: 4)
        try Data([1,2,3,4]).write(to: a.attachments.fileURL(for: ref))
        var note = Note(title: "PRIVATE-ORIGINAL", category: .personal, attachments: [ref])
        #expect(a.saveNote(note))
        _ = try await left.configure(config, credentials: credentials, recovery: code, create: true)
        await left.sync(); #expect(left.error == nil)
        _ = try await right.configure(config, credentials: credentials, recovery: code, create: false)
        await right.sync(); #expect(right.error == nil)
        #expect(b.notes.first?.title == note.title)
        #expect(try Data(contentsOf: b.attachments.fileURL(for: ref)) == Data([1,2,3,4]))
        note.title = "PRIVATE-LEFT"; #expect(a.saveNote(note))
        var other = try #require(b.notes.first); other.title = "PRIVATE-RIGHT"; #expect(b.saveNote(other))
        await left.sync(); #expect(left.error == nil)
        await right.sync(); #expect(right.error == nil && right.conflicts.count == 1)
        await left.sync(); #expect(left.error == nil && left.conflicts.count == 1)
        #expect(a.notes.first?.title == b.notes.first?.title)
        let conflict = try #require(right.conflicts.first)
        let chosen = try #require(conflict.heads.first { $0.payload?["title"]?.string == "PRIVATE-RIGHT" })
        await right.resolve(conflict, choosing: chosen)
        #expect(right.error == nil)
        await left.sync(); #expect(left.error == nil && left.conflicts.isEmpty)
        #expect(a.notes.first?.title == "PRIVATE-RIGHT")
        let task = TaskItem(title: "PRIVATE-RETRY")
        #expect(a.saveTask(task))
        transport.failNextWrite()
        await left.sync()
        #expect(left.error != nil && a.tasks.contains { $0.id == task.id })
        await left.sync(); #expect(left.error == nil)
        await right.sync(); #expect(right.error == nil && b.tasks.contains { $0.id == task.id })
        #expect(transport.snapshot().values.allSatisfy { $0.range(of: Data("PRIVATE-".utf8)) == nil })
    }

    @Test func listPaginationAndConditionalWritesUseTheServerContract() async throws {
        let transport = MemoryS3(), host = "\(UUID().uuidString.lowercased()).test.invalid"
        MemoryS3Protocol.register(transport, host: host)
        defer { MemoryS3Protocol.unregister(host: host) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MemoryS3Protocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let client = S3Client(configuration: .init(endpoint: "https://\(host)", bucket: "test"), credentials: .init(accessKey: "fake", secretKey: "fake"), session: session)
        for i in 0..<4 { try await client.put(Data([UInt8(i)]), key: "nook/空 格/\(i)", createOnly: true) }
        #expect(try await client.list(prefix: "nook/").count == 4)
        await #expect(throws: (any Error).self) { try await client.put(Data([9]), key: "nook/空 格/0", createOnly: true) }
        #expect(try await client.get("nook/空 格/0") == Data([0]))
    }
}

private final class MemoryS3: @unchecked Sendable {
    private let lock = NSLock()
    private var objects: [String: Data] = [:]
    private var nextWriteFails = false
    func failNextWrite() { lock.withLock { nextWriteFails = true } }
    func snapshot() -> [String: Data] { lock.withLock { objects } }
    func response(_ request: URLRequest) throws -> (Int, Data) {
        // URLProtocol may represent a request body as a stream, just like a real transport.
        let body: Data
        if let data = request.httpBody { body = data }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw URLError(.cannotDecodeContentData) }
                if count == 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        } else { body = Data() }
        return lock.withLock {
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let key = String(parts.path.split(separator: "/").dropFirst().joined(separator: "/"))
            let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if request.httpMethod == "PUT" {
                if nextWriteFails { nextWriteFails = false; return (503, Data()) }
                if request.value(forHTTPHeaderField: "If-None-Match") == "*", objects[key] != nil { return (412, Data()) }
                objects[key] = body; return (200, Data())
            }
            if query["list-type"] == "2" {
                let keys = objects.keys.filter { $0.hasPrefix(query["prefix"] ?? "") }.sorted()
                let offset = Int(query["continuation-token"] ?? "0") ?? 0
                let page = Array(keys.dropFirst(offset).prefix(2))
                let next = offset + page.count, truncated = next < keys.count
                let xml = "<ListBucketResult><IsTruncated>\(truncated)</IsTruncated>" +
                    page.map { "<Contents><Key>\(S3Client.escape($0))</Key></Contents>" }.joined() +
                    (truncated ? "<NextContinuationToken>\(next)</NextContinuationToken>" : "") + "</ListBucketResult>"
                return (200, Data(xml.utf8))
            }
            return objects[key].map { (200, $0) } ?? (404, Data())
        }
    }
}

private final class MemoryS3Protocol: URLProtocol, @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var services: [String: MemoryS3] = [:]
    }
    private static let registry = Registry()
    static func register(_ service: MemoryS3, host: String) { registry.lock.withLock { registry.services[host] = service } }
    static func unregister(host: String) { _ = registry.lock.withLock { registry.services.removeValue(forKey: host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let host = request.url?.host, let service = Self.registry.lock.withLock({ Self.registry.services[host] }) else { throw URLError(.cannotFindHost) }
            let (status, data) = try service.response(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
