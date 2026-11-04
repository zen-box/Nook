import Clibsodium
import CommonCrypto
import CryptoKit
import Foundation
import NookCore

/// Local vault v2: Argon2id v1.3 (32-byte output, p=1), XChaCha20-Poly1305.
/// Sealed bytes = random 24-byte nonce || ciphertext || 16-byte tag.
/// Version 1 is read only so existing installations can migrate without losing entries.
enum VaultCrypto {
    static let keyVersion = 2
    static let minimumPasswordLength = 8

    struct KDFParameters: Sendable {
        var operations: Int
        var memoryBytes: Int
        static let standard = Self(operations: 3, memoryBytes: 64 * 1024 * 1024)
        static let testing = Self(operations: 1, memoryBytes: 8 * 1024 * 1024)
    }

    enum Failure: Error {
        case wrongPassword
        case corrupted
        case keyDerivation
        case unsupportedVersion
    }

    private static func wrapContext(version: Int) -> Data {
        Data("nook.vault.key.v\(version)".utf8)
    }

    private static func checkValue(version: Int) -> Data {
        Data("nook.vault.key-check.v\(version)".utf8)
    }

    static func makeVaultKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func makeSalt() -> Data {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    }

    static func deriveKey(password: String, salt: Data, parameters: KDFParameters) throws -> SymmetricKey {
        guard sodium_init() >= 0, salt.count == 16,
              (1...10).contains(parameters.operations),
              (8 * 1024 * 1024...256 * 1024 * 1024).contains(parameters.memoryBytes)
        else { throw Failure.keyDerivation }
        var derived = [UInt8](repeating: 0, count: 32)
        // Use the C entry point: preserves UTF-8 bytes, including Chinese and embedded NULs.
        let status = try password.utf8CString.withUnsafeBufferPointer { bytes in
            guard let passwordBytes = bytes.baseAddress else { throw Failure.keyDerivation }
            return crypto_pwhash(&derived, 32, passwordBytes, UInt64(bytes.count - 1),
                          [UInt8](salt), UInt64(parameters.operations), size_t(parameters.memoryBytes),
                          crypto_pwhash_alg_argon2id13())
        }
        guard status == 0 else { throw Failure.keyDerivation }
        return SymmetricKey(data: derived)
    }

    static func passwordKey(_ password: String, record: VaultKeyRecord) throws -> SymmetricKey {
        switch record.version {
        case 1: return try legacyKey(password: password, salt: record.salt, rounds: record.rounds)
        case keyVersion:
            return try deriveKey(password: password, salt: record.salt,
                                 parameters: .init(operations: record.rounds, memoryBytes: record.memoryLimit))
        default: throw Failure.unsupportedVersion
        }
    }

    static func wrap(_ vaultKey: SymmetricKey, with passwordKey: SymmetricKey) throws -> Data {
        try encrypt(vaultKey.withUnsafeBytes { Data($0) }, with: passwordKey, aad: wrapContext(version: keyVersion))
    }

    static func unwrap(_ wrapped: Data, with passwordKey: SymmetricKey, version: Int) throws -> SymmetricKey {
        let raw: Data
        do {
            raw = try decrypt(wrapped, with: passwordKey, aad: wrapContext(version: version), version: version)
        } catch Failure.unsupportedVersion {
            throw Failure.unsupportedVersion
        } catch {
            throw Failure.wrongPassword
        }
        guard raw.count == 32 else { throw Failure.corrupted }
        return SymmetricKey(data: raw)
    }

    static func makeKeyCheck(_ vaultKey: SymmetricKey) throws -> Data {
        try encrypt(checkValue(version: keyVersion), with: vaultKey, aad: Data())
    }

    static func isKey(_ vaultKey: SymmetricKey, matching keyCheck: Data, version: Int) -> Bool {
        (try? decrypt(keyCheck, with: vaultKey, aad: Data(), version: version)) == checkValue(version: version)
    }

    static func seal(_ item: VaultItem, with vaultKey: SymmetricKey) throws -> Data {
        try encrypt(NookJSON.makeEncoder().encode(item), with: vaultKey,
                    aad: associatedData(id: item.id, version: keyVersion))
    }

    static func open(_ sealed: Data, id: UUID, category: VaultCategory, version: Int, with vaultKey: SymmetricKey) throws -> VaultItem {
        let json = try decrypt(sealed, with: vaultKey, aad: associatedData(id: id, version: version), version: version)
        let item = try NookJSON.makeDecoder().decode(VaultItem.self, from: json)
        guard item.id == id, item.category == category else { throw Failure.corrupted }
        return item
    }

    static func associatedData(id: UUID, version: Int) -> Data {
        if version == 1 { return Data("nook.vault.item|\(id.uuidString.lowercased())|v1".utf8) }
        return Data("nook|\(id.uuidString.lowercased())|vault|v\(version)".utf8)
    }

    static func encrypt(_ message: Data, with key: SymmetricKey, aad: Data) throws -> Data {
        guard sodium_init() >= 0, key.bitCount == 256 else { throw Failure.corrupted }
        var nonce = [UInt8](repeating: 0, count: 24)
        randombytes_buf(&nonce, 24)
        var ciphertext = [UInt8](repeating: 0, count: message.count + 16)
        var length: UInt64 = 0
        let status = crypto_aead_xchacha20poly1305_ietf_encrypt(
            &ciphertext, &length, [UInt8](message), UInt64(message.count),
            [UInt8](aad), UInt64(aad.count), nil, nonce, key.withUnsafeBytes { Array($0) })
        guard status == 0, length == UInt64(ciphertext.count) else { throw Failure.corrupted }
        return Data(nonce + ciphertext)
    }

    static func decrypt(_ sealed: Data, with key: SymmetricKey, aad: Data, version: Int) throws -> Data {
        if version == 1 {
            return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: sealed), using: key, authenticating: aad)
        }
        guard version == keyVersion else { throw Failure.unsupportedVersion }
        guard sodium_init() >= 0, sealed.count >= 40, key.bitCount == 256 else { throw Failure.corrupted }
        let nonce = [UInt8](sealed.prefix(24))
        let ciphertext = [UInt8](sealed.dropFirst(24))
        var message = [UInt8](repeating: 0, count: ciphertext.count - 16)
        var length: UInt64 = 0
        let status = crypto_aead_xchacha20poly1305_ietf_decrypt(
            &message, &length, nil, ciphertext, UInt64(ciphertext.count),
            [UInt8](aad), UInt64(aad.count), nonce, key.withUnsafeBytes { Array($0) })
        guard status == 0, length == UInt64(message.count) else { throw Failure.corrupted }
        return Data(message)
    }

    /// Read-only compatibility for the previous implementation.
    static func legacyKey(password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        guard (1...10_000_000).contains(rounds) else { throw Failure.keyDerivation }
        var derived = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
                                         [UInt8](salt), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                         UInt32(rounds), &derived, 32)
        guard status == Int32(kCCSuccess) else { throw Failure.keyDerivation }
        return SymmetricKey(data: derived)
    }
}
