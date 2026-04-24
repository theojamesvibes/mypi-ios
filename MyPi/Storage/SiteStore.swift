import Foundation

/// Persists `Site` metadata to disk (API keys excluded — those live in Keychain).
final class SiteStore {
    static let shared = SiteStore()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("sites.json")
    }()

    private init() {}

    func load() -> [Site] {
        guard let data = try? Data(contentsOf: fileURL),
              let sites = try? JSONDecoder().decode([Site].self, from: data) else { return [] }
        return sites.sorted { $0.sortOrder < $1.sortOrder }
    }

    func save(_ site: Site) {
        var sites = load()
        if let idx = sites.firstIndex(where: { $0.id == site.id }) {
            sites[idx] = site
        } else {
            var mutable = site
            mutable = Site(
                id: site.id,
                name: site.name,
                baseURL: site.baseURL,
                allowSelfSigned: site.allowSelfSigned,
                pinnedCertFingerprint: site.pinnedCertFingerprint,
                sortOrder: sites.count
            )
            sites.append(mutable)
        }
        try? JSONEncoder().encode(sites).write(to: fileURL, options: .atomic)
    }

    func delete(id: UUID) {
        var sites = load()
        sites.removeAll { $0.id == id }
        // Re-number sort order.
        let renumbered = sites.enumerated().map { idx, s in
            Site(id: s.id, name: s.name, baseURL: s.baseURL,
                 allowSelfSigned: s.allowSelfSigned,
                 pinnedCertFingerprint: s.pinnedCertFingerprint,
                 sortOrder: idx)
        }
        try? JSONEncoder().encode(renumbered).write(to: fileURL, options: .atomic)
        KeychainStore.shared.deleteAPIKey(for: id)
        KeychainStore.shared.deleteCertFingerprint(for: id)
        // Sweep every per-site cache file. Prefix-delete covers dashboard
        // (summary/history/top/sync) and querylog (clients + queries per
        // filter × range) variants without having to enumerate the cross
        // product here.
        DiskCache.shared.deleteAll(withPrefix: "dashboard-\(id.uuidString)")
        DiskCache.shared.deleteAll(withPrefix: "querylog-\(id.uuidString)")
    }
}
