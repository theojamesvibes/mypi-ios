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

    func certFingerprint(for siteID: UUID) -> String? {
        load(account: "cert-\(siteID.uuidString)")
    }

    func deleteCertFingerprint(for siteID: UUID) {
        delete(account: "cert-\(siteID.uuidString)")
    }

    // MARK: - Private helpers

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
        SecItemAdd(query as CFDictionary, nil)
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
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
