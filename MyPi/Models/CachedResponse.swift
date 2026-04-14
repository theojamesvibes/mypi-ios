import Foundation

/// Wrapper persisted to disk so the last successful payload survives app restart.
struct CachedResponse<T: Codable>: Codable {
    let data: T
    let fetchedAt: Date
}
