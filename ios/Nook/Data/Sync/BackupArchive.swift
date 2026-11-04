import Foundation
import NookCore

struct StagedArchive: Sendable {
    var dataset: PortableDataset
    var folder: URL
    var refs: [FileRef]
}
/// Framed, authenticated archive. One attachment is read at a time, avoiding a base64 copy of
/// the entire photo/audio library. Every frame is bound to the archive and immutable file ID.
enum BackupArchive {
    private struct Manifest: Codable {
        var format = "nook.backup.encrypted"
        var version = 1
        var values: [String: JSONValue]
        var refs: [FileRef]
    }
    static func write(values: [String: JSONValue], refs: [FileRef], folder: URL, key: Data) throws -> URL {
        let id = UUID()
        let target = FileManager.default.temporaryDirectory.appending(path: "Nook-\(id).nookbackup")
        guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: target)
        do {
            try handle.write(contentsOf: Data("NOOKBK01\(id.uuidString)".utf8))
            let manifest = try NookJSON.makeEncoder().encode(Manifest(values: values, refs: refs))
            try frame(SyncCrypto.seal(manifest, key: key, context: "backup/\(id)/manifest"), to: handle)
            for ref in refs {
                let url = attachmentURL(ref, folder: folder)
                let bytes = try Data(contentsOf: url)
                guard ref.byteCount.map({ $0 == bytes.count }) ?? true else { throw SyncError.missingAttachment }
                try frame(SyncCrypto.seal(bytes, key: key, context: "backup/\(id)/file/\(ref.id)"), to: handle)
            }
            try handle.close(); return target
        } catch {
            try? handle.close(); try? FileManager.default.removeItem(at: target); throw error
        }
    }
    static func read(_ source: URL, key: Data) throws -> StagedArchive {
        let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
        let header = try exact(44, from: handle)
        guard String(data: header.prefix(8), encoding: .utf8) == "NOOKBK01",
              let text = String(data: header.suffix(36), encoding: .utf8), let id = UUID(uuidString: text) else { throw SyncError.wrongLibrary }
        let encrypted = try readFrame(handle)
        guard let data = try? SyncCrypto.open(encrypted, key: key, context: "backup/\(id)/manifest") else { throw SyncError.invalidRecoveryCode }
        let manifest = try NookJSON.makeDecoder().decode(Manifest.self, from: data)
        guard manifest.format == "nook.backup.encrypted", manifest.version == 1,
              Set(manifest.refs.map(\.id)).count == manifest.refs.count,
              manifest.refs.count <= 100_000 else { throw SyncError.invalidHistory }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Nook-Import-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        do {
            for ref in manifest.refs {
                let bytes = try SyncCrypto.open(readFrame(handle), key: key, context: "backup/\(id)/file/\(ref.id)")
                guard ref.byteCount.map({ $0 == bytes.count }) ?? true else { throw SyncError.missingAttachment }
                try bytes.write(to: attachmentURL(ref, folder: folder), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            guard (try handle.read(upToCount: 1))?.isEmpty != false else { throw SyncError.invalidHistory }
            return .init(dataset: .init(values: manifest.values, files: []), folder: folder, refs: manifest.refs)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    @MainActor static func install(_ staged: StagedArchive, into store: AppStore) throws {
        for ref in staged.refs {
            let source = attachmentURL(ref, folder: staged.folder), target = store.attachments.fileURL(for: ref)
            if FileManager.default.fileExists(atPath: target.path) {
                guard try Data(contentsOf: source) == Data(contentsOf: target) else { throw SyncError.missingAttachment }
            } else { try FileManager.default.copyItem(at: source, to: target) }
        }
        try store.installPortable(staged.dataset)
    }
    static func attachmentURL(_ ref: FileRef, folder: URL) -> URL {
        folder.appending(path: "\(ref.id.uuidString.lowercased()).\(ref.kind == .image ? "jpg" : ref.kind == .audio ? "m4a" : "bin")")
    }
    private static func frame(_ bytes: Data, to handle: FileHandle) throws {
        guard bytes.count <= 100 * 1024 * 1024 else { throw S3Error.tooLarge }
        var size = UInt32(bytes.count).bigEndian
        try handle.write(contentsOf: withUnsafeBytes(of: &size) { Data($0) }); try handle.write(contentsOf: bytes)
    }
    private static func readFrame(_ handle: FileHandle) throws -> Data {
        let data = try exact(4, from: handle)
        let size = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= 100 * 1024 * 1024 else { throw S3Error.tooLarge }
        return try exact(Int(size), from: handle)
    }
    private static func exact(_ count: Int, from handle: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let part = try handle.read(upToCount: count - result.count), !part.isEmpty else { throw SyncError.invalidHistory }
            result.append(part)
        }
        return result
    }
}
