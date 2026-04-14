import Foundation

/// Simple disk cache. Stores the last successful API response per cache key so
/// the app can show stale data when the network is unavailable.
final class DiskCache {
    static let shared = DiskCache()

    private let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("net.myssdomain.mypi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    func write<T: Encodable>(_ value: T, key: String) {
        let wrapper = CachedResponse(data: value, fetchedAt: Date())
        guard let data = try? JSONEncoder().encode(wrapper) else { return }
        let url = directory.appendingPathComponent(sanitize(key))
        try? data.write(to: url, options: .atomic)
    }

    func read<T: Decodable>(key: String, as type: T.Type) -> CachedResponse<T>? {
        let url = directory.appendingPathComponent(sanitize(key))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedResponse<T>.self, from: data)
    }

    func delete(key: String) {
        let url = directory.appendingPathComponent(sanitize(key))
        try? FileManager.default.removeItem(at: url)
    }

    private func sanitize(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
           .replacingOccurrences(of: ":", with: "_")
    }
}
