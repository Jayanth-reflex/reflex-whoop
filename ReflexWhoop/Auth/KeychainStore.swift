import Foundation
import Security

/// Minimal generic-password Keychain wrapper. No third-party dependency for
/// something this small; every call is one `SecItem*` round-trip.
enum KeychainStore {
    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    /// `.afterFirstUnlock` (not `.whenUnlocked`) so a background sync task can
    /// refresh the access token while the phone is locked — `BGAppRefreshTask` can
    /// fire in that state and would otherwise fail every refresh attempt.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlock

    static func set(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        // Delete-then-add is the standard pattern for "upsert" with Keychain, and
        // matters here specifically: SecItemUpdate alone won't create a missing
        // item, and SecItemAdd alone errors if one already exists.
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessibility

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func get(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static let service = "com.reflexwhoop.app"
}
