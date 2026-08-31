import Foundation
import LocalAuthentication
import Security

enum KeychainError: Error, LocalizedError {
    case accessControlUnavailable(String)
    case unhandled(OSStatus)
    case unexpectedData

    var errorDescription: String? {
        switch self {
        case .accessControlUnavailable(let message):
            return "SecAccessControlCreateWithFlags failed: \(message)"
        case .unhandled(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "OSStatus \(status): \(message)"
        case .unexpectedData:
            return "The stored item was not valid UTF-8"
        }
    }
}

/// A Keychain item guarded by biometry, mirroring what a banking app does with a
/// key that requires user authentication on every use.
enum KeychainStore {
    static let service = "com.magicpod.biometricdemo"
    static let account = "demo-secret"
    static let demoSecret = "s3cr3t-42"

    static func save(secret: String) throws {
        delete()

        var accessControlError: Unmanaged<CFError>?
        // .biometryCurrentSet invalidates the item as soon as the enrolled set
        // changes — the iOS counterpart of Android's
        // setInvalidatedByBiometricEnrollment(true).
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &accessControlError
        ) else {
            let message = (accessControlError?.takeRetainedValue() as Error?)?.localizedDescription
                ?? "unknown"
            throw KeychainError.accessControlUnavailable(message)
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessControl as String: accessControl,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    static func read(prompt: String) throws -> String {
        let context = LAContext()
        context.localizedReason = prompt

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return secret
    }

    @discardableResult
    static func delete() -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary)
    }
}
