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
            // Mutate rather than re-construct — re-constructing via
            // `Site.init(id:name:baseURL:...)` silently drops any field
            // not in the argument list, which is how `isDemo` got lost in
            // 0.1.6. Mutation is future-proof: new fields just travel with
            // the existing struct.
            var mutable = site
            mutable.sortOrder = sites.count
            sites.append(mutable)
        }
        try? JSONEncoder().encode(sites).write(to: fileURL, options: .atomic)
    }

    func delete(id: UUID) {
        var sites = loadQuiet()
        sites.removeAll { $0.id == id }
        // Re-number sort order — same mutation-not-reconstruction rule as
        // save() so we don't lose fields on the renumber pass.
        let renumbered: [Site] = sites.enumerated().map { idx, s in
            var updated = s
            updated.sortOrder = idx
            return updated
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
