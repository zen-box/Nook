import Foundation
import CryptoKit
import NookCore

struct SyncLibrary: Codable, Sendable {
    var format = "nook.library"
    var version = 1
    var id: UUID
    var keyCheck: Data
}
enum SyncCrypto {
    static func makeKey() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }
    static func code(_ data: Data) -> String { "NOOK1." + Base64URL.encode(data) }
    static func key(from code: String) throws -> Data {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("NOOK1."), let data = Base64URL.decode(String(normalized.dropFirst(6))), data.count == 32 else { throw SyncError.invalidRecoveryCode }
        return data
    }
    private static func derived(_ key: Data, context: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: key), salt: Data("nook.e2ee.v1".utf8), info: Data(context.utf8), outputByteCount: 32)
    }
    static func seal(_ data: Data, key: Data, context: String) throws -> Data {
        guard key.count == 32 else { throw SyncError.invalidRecoveryCode }
        guard let combined = try AES.GCM.seal(data, using: derived(key, context: context), authenticating: Data(context.utf8)).combined else { throw SyncError.invalidHistory }
        return combined
    }
    static func open(_ data: Data, key: Data, context: String) throws -> Data {
        guard key.count == 32 else { throw SyncError.invalidRecoveryCode }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: derived(key, context: context), authenticating: Data(context.utf8))
    }
    static func validate(_ library: SyncLibrary, key: Data) throws {
        guard library.format == "nook.library", library.version == 1,
              (try? open(library.keyCheck, key: key, context: "library/\(library.id)")) == Data("Nook library key check v1".utf8) else { throw SyncError.invalidRecoveryCode }
    }
}
