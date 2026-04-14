import Foundation

/// A configured MyPi server connection.
struct Site: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    /// Base URL of the MyPi server, e.g. "https://mypi.home.example.com"
    var baseURL: URL
    /// Whether to allow self-signed / unverified TLS certificates.
    var allowSelfSigned: Bool
    /// SHA-256 fingerprint of a pinned certificate (hex, no colons), only used when allowSelfSigned == true.
    var pinnedCertFingerprint: String?
    /// Display order index.
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        allowSelfSigned: Bool = false,
        pinnedCertFingerprint: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.allowSelfSigned = allowSelfSigned
        self.pinnedCertFingerprint = pinnedCertFingerprint
        self.sortOrder = sortOrder
    }
}
