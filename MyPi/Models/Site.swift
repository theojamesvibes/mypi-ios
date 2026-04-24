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
    /// Demo site flag. When true, `APIClient` returns canned `DemoData`
    /// responses instead of hitting the network — used to let App Store
    /// reviewers (and curious users) explore the UI without configuring a
    /// real MyPi server.
    var isDemo: Bool

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        allowSelfSigned: Bool = false,
        pinnedCertFingerprint: String? = nil,
        sortOrder: Int = 0,
        isDemo: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.allowSelfSigned = allowSelfSigned
        self.pinnedCertFingerprint = pinnedCertFingerprint
        self.sortOrder = sortOrder
        self.isDemo = isDemo
    }

    /// Backward-compatible decoder — `isDemo` was added in 0.1.6, so
    /// `sites.json` written by older builds won't have the key. Decoding
    /// as an optional and defaulting to `false` keeps the migration path
    /// seamless (no one-shot rewrite needed).
    ///
    /// Also self-heals the 0.1.6 demo-mode bug where `SiteStore.save`
    /// reconstructed sites without `isDemo` and wrote them to disk with
    /// the flag cleared. Any site pointing at the canonical demo host —
    /// `demo.mypi.invalid`, which can never resolve on the real internet
    /// (RFC 2606 reserves `.invalid`) — is forced back to demo on load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        baseURL = try c.decode(URL.self, forKey: .baseURL)
        allowSelfSigned = try c.decode(Bool.self, forKey: .allowSelfSigned)
        pinnedCertFingerprint = try c.decodeIfPresent(String.self, forKey: .pinnedCertFingerprint)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        let decodedIsDemo = try c.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
        isDemo = decodedIsDemo || baseURL.host()?.lowercased() == "demo.mypi.invalid"
    }
}
