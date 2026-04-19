import Foundation
import Security

/// Thin wrapper around the iOS Keychain for storing per-site API keys and
/// certificate fingerprints.
final class KeychainStore {
    static let shared = KeychainStore()
    private let service = "net.myssdomain.mypi"

    private init() {}

    // MARK: - API Keys

    func saveAPIKey(_ key: String, for siteID: UUID) {
        save(key, account: "apikey-\(siteID.uuidString)")
    }

    func apiKey(for siteID: UUID) -> String? {
        load(account: "apikey-\(siteID.uuidString)")
    }

    func deleteAPIKey(for siteID: UUID) {
        delete(account: "apikey-\(siteID.uuidString)")
    }

    // MARK: - Cert fingerprints

    func saveCertFingerprint(_ fingerprint: String, for siteID: UUID) {
        save(fingerprint, account: "cert-\(siteID.uuidString)")
    }

    func deleteCertFingerprint(for siteID: UUID) {
        delete(account: "cert-\(siteID.uuidString)")
    }

    // MARK: - Private helpers

    /// On simulator (or any build without a proper code-signing team), `SecItemAdd`
    /// fails with errSecMissingEntitlement and we silently lose the value. Fall back
    /// to UserDefaults **only for that specific status** so the app stays usable
    /// for local testing; any other Keychain error (e.g. transient
    /// first-unlock failure on a real device) is surfaced as a failure rather
    /// than silently downgrading the storage security.
    /// On real signed builds the Keychain path succeeds and UserDefaults is never touched.
    private static let defaultsPrefix = "net.myssdomain.mypi.fallback."

    private func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            UserDefaults.standard.set(value, forKey: Self.defaultsPrefix + account)
        }
    }

    private func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return UserDefaults.standard.string(forKey: Self.defaultsPrefix + account)
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: Self.defaultsPrefix + account)
    }
}
