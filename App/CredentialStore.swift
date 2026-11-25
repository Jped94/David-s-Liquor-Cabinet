import CellarKit
import Foundation
import Security

/// Stores the CellarTracker login in the iOS Keychain.
///
/// The item is readable after the first unlock (so a background refresh
/// could use it), never syncs to iCloud, and never leaves this device.
enum CredentialStore {
    private static let service = "LiquorCabinet.CellarTracker"
    private static let account = "default"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> CellarTrackerCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(CellarTrackerCredentials.self, from: data)
    }

    static func save(_ credentials: CellarTrackerCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        delete()
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Couldn't save the login to the Keychain (error \(status))." }
}
