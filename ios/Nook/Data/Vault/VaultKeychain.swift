import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct KeychainError: Error {
    let status: OSStatus
}

/// A device-only key whose access control is enforced by Keychain itself.
struct VaultKeychain: Sendable {
    var service = "com.nook.personal.vault"
    var account = "vault-key.user-presence.v2"

    func store(_ key: SymmetricKey) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error
        ) else { throw KeychainError(status: errSecParam) }
        delete()
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Check metadata only. Never fetch the secret while deciding whether to show the button.
    var containsProtectedKey: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // An ACL-protected item may refuse a noninteractive query. It still exists;
        // authentication belongs in load(), not in the visibility check.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// The read itself requires Face ID, Touch ID or device passcode authorization.
    func load(reason: String) async throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = reason
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw KeychainError(status: errSecAuthFailed)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, data.count == 32 else { throw KeychainError(status: errSecDecode) }
        return SymmetricKey(data: data)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    /// Remove the earlier copy which did not have user-presence access control.
    func deleteLegacyKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "vault-key",
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

/// Face ID, Touch ID or the device passcode.
enum DeviceAuthentication {
    /// Whether the device can authenticate the owner at all (a passcode is set).
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return String(localized: "Face ID")
        case .touchID: return String(localized: "Touch ID")
        case .opticID: return String(localized: "Optic ID")
        default: return String(localized: "Passcode")
        }
    }

    static var methodSymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.open"
        }
    }

}
