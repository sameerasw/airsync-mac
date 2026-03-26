import Foundation
import Security

/// Thin wrapper around the macOS Keychain.
///
/// With ad-hoc ("Sign to Run Locally") code signing, **every** individual
/// `SecItem*` call triggers a macOS password-prompt dialog.  To avoid
/// pestering the user with 5-8 prompts at launch we:
///
///   1. Call `preload()` once at startup, which issues a **single**
///      `SecItemCopyMatching` with `kSecMatchLimitAll` to fetch every
///      item belonging to our service in one shot → **one prompt**.
///   2. Cache all values in memory.  Subsequent reads come from the
///      cache — zero prompts.
///   3. Writes update both the cache and the Keychain.  Because the
///      Keychain ACL for the item was already approved during the
///      preload read, writes within the same app session usually
///      succeed without an additional prompt.
enum KeychainStorage {
    private static let service = "com.sameerasw.airsync.trial"

    /// In-memory cache: account key → raw Data value.
    private static var cache: [String: Data] = [:]
    /// True once `preload()` has completed (successfully or not).
    private static var didPreload = false
    private static let lock = NSLock()

    // MARK: - Preload (call once at app launch)

    /// Reads **all** keychain items for our service in a single query.
    /// This triggers at most **one** macOS password prompt instead of
    /// one per key.  Call this as early as possible — ideally before
    /// any other Keychain-dependent code runs.
    static func preload() {
        lock.lock()
        guard !didPreload else { lock.unlock(); return }
        didPreload = true
        lock.unlock()

        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecMatchLimit as String:   kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String:  true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            #if DEBUG
            if status != errSecItemNotFound {
                print("[Keychain] preload: SecItemCopyMatching returned \(status)")
            }
            #endif
            return
        }

        lock.lock()
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               let data = item[kSecValueData as String] as? Data {
                cache[account] = data
            }
        }
        lock.unlock()

        #if DEBUG
        print("[Keychain] preload: cached \(items.count) item(s)")
        #endif
    }

    // MARK: - Read

    static func string(for key: String) -> String? {
        guard let data = data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func data(for key: String) -> Data? {
        lock.lock()
        if didPreload, let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Fallback: individual query (only reached if preload was not
        // called or the key was added after preload).
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        // Back-fill the cache so future reads don't hit the Keychain.
        lock.lock()
        cache[key] = data
        lock.unlock()

        return data
    }

    // MARK: - Write

    static func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        setData(data, for: key)
    }

    static func setData(_ data: Data, for key: String) {
        // Update cache first — even if the Keychain write fails, the
        // in-process value stays consistent for the current session.
        lock.lock()
        cache[key] = data
        lock.unlock()

        var query = baseQuery(for: key)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
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

    // MARK: - Delete

    static func delete(key: String) {
        lock.lock()
        cache.removeValue(forKey: key)
        lock.unlock()

        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Helpers

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key
        ]
    }
}
