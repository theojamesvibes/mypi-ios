import Foundation

/// Decoded shape of one entry in `GET /api/sites` from a multi-site
/// MyPi server (server version 1.11+). Single-site / legacy servers
/// either don't expose this endpoint (returns 404) or return one row.
///
/// We use the slug for URL routing and the name for display. UUID is
/// kept around so future server features that key off it (per-key
/// site scoping, audit trails) don't require another model change.
struct MyPiSite: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let slug: String
    let isMain: Bool
    let isActive: Bool
    let sortOrder: Int
    let instanceCount: Int
    let activeInstanceCount: Int
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case isMain = "is_main"
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case instanceCount = "instance_count"
        case activeInstanceCount = "active_instance_count"
        case createdAt = "created_at"
    }
}
