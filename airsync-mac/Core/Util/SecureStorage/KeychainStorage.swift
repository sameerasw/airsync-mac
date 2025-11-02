import Foundation
import Security

enum KeychainStorage {
    private static let service = "com.sameerasw.airsync.trial"

    static func string(for key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }

    var query = baseQuery(for: key)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery = baseQuery(for: key)
            let attributes: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        } else if status == errSecSuccess {
            // Item added; no further action required.
        } else {
            #if DEBUG
            print("[Keychain] Failed to store value for \(key): status \(status)")
            #endif
        }
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [:]
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrService as String] = service
        query[kSecAttrAccount as String] = key
        return query
    }
}
