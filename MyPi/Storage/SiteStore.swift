import Foundation

/// Raised by `SiteStore.load()` when `sites.json` exists but can't be
/// decoded. The "file is missing" case is not an error — it's the fresh
/// install state, handled by returning `[]`.
enum SiteStoreError: LocalizedError {
    case corrupted(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .corrupted:
            return "Couldn't read your saved sites. The sites file on this device appears to be corrupted."
        }
    }
}

/// Persists `Site` metadata to disk (API keys excluded — those live in Keychain).
final class SiteStore {
    static let shared = SiteStore()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("sites.json")
    }()

    private init() {}

    /// Read the persisted `[Site]` array.
    ///
    /// - returns: empty array if the file doesn't exist yet (fresh install).
    /// - throws: `SiteStoreError.corrupted` if the file exists but can't be
    ///   decoded. We throw rather than silently returning `[]` so the UI
    ///   can warn the user instead of dropping them into the onboarding
    ///   flow as if no sites had ever been configured — otherwise a one-off
    ///   decode bug or partial write would look like "all my sites vanished".
    func load() throws -> [Site] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SiteStoreError.corrupted(underlying: error)
        }
        do {
            let sites = try JSONDecoder().decode([Site].self, from: data)
            return sites.sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            throw SiteStoreError.corrupted(underlying: error)
        }
    }

    /// Convenience for the hot path where we've already surfaced any load
    /// error elsewhere — used by `save`/`delete` when they need the current
    /// on-disk list to append to. Falls back to `[]` on any failure because
    /// throwing inside a mutation path would leave the file in a worse
    /// state than the one we're trying to rewrite.
    private func loadQuiet() -> [Site] {
        (try? load()) ?? []
    }

    func save(_ site: Site) {
        var sites = loadQuiet()
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
        var sites = loadQuiet()
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
