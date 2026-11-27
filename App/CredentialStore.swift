import CellarKit
import Foundation
import Security

/// Small wrapper over the iOS Keychain for this app's secrets. Items are
/// readable after the first unlock, never sync to iCloud, and never leave
/// this device.
enum Keychain {
    static func read(service: String, account: String = "default") -> Data? {
        var query = baseQuery(service, account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data, service: String, account: String = "default") throws {
        delete(service: service, account: account)
        var attributes = baseQuery(service, account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func delete(service: String, account: String = "default") {
        SecItemDelete(baseQuery(service, account) as CFDictionary)
    }

    private static func baseQuery(_ service: String, _ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// The CellarTracker login, kept only on the iPad(s) used to sync. It's
/// sent to the cabinet server for each sync and never stored there.
enum CredentialStore {
    private static let service = "LiquorCabinet.CellarTracker"

    static func load() -> CellarTrackerCredentials? {
        Keychain.read(service: service).flatMap { try? JSONDecoder().decode(CellarTrackerCredentials.self, from: $0) }
    }

    static func save(_ credentials: CellarTrackerCredentials) throws {
        try Keychain.write(JSONEncoder().encode(credentials), service: service)
    }

    static func delete() {
        Keychain.delete(service: service)
    }
}

/// The guest session for reading the menu, created with the app's built-in
/// key and remembered so it isn't requested on every launch.
enum GuestSessionStore {
    private static let service = "LiquorCabinet.GuestSession"

    static func load() -> String? {
        Keychain.read(service: service).map { String(decoding: $0, as: UTF8.self) }
    }

    static func save(_ token: String) {
        try? Keychain.write(Data(token.utf8), service: service)
    }

    static func delete() {
        Keychain.delete(service: service)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Couldn't save to the Keychain (error \(status))." }
}

/// Values from the build settings (Config/App.xcconfig and the git-ignored
/// Config/Secrets.xcconfig), read from Info.plist.
enum AppConfig {
    /// The cabinet server, or `nil` if the build doesn't name one.
    static var serverURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "CabinetServerHost") as? String)
            .flatMap(ServerClient.baseURL(host:))
    }

    /// The key that lets this app read the menu without a passcode prompt.
    static var appKey: String? {
        guard let key = (Bundle.main.object(forInfoDictionaryKey: "CabinetAppKey") as? String)?
            .trimmingCharacters(in: .whitespaces),
            !key.isEmpty, !key.hasPrefix("paste-")
        else { return nil }
        return key
    }
}
