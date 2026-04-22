import Foundation

// MARK: - Health

struct HealthResponse: Decodable {
    let version: String
    let statsPollInterval: Int
    let queriesPollInterval: Int

    enum CodingKeys: String, CodingKey {
        case version
        case statsPollInterval = "stats_poll_interval"
        case queriesPollInterval = "queries_poll_interval"
    }
}

// MARK: - Summary / Dashboard

struct AggregatedSummary: Codable {
    let totals: SummaryStats
    let instances: [InstanceSummary]
}

struct SummaryStats: Codable {
    let dnsQueriesToday: Int
    let queriesBlocked: Int
    let percentBlocked: Double
    let domainsOnBlocklist: Int
    let uniqueClients: Int
    let queriesCached: Int
    let queriesForwarded: Int

    enum CodingKeys: String, CodingKey {
        case dnsQueriesToday = "dns_queries_today"
        case queriesBlocked = "queries_blocked"
        case percentBlocked = "percent_blocked"
        case domainsOnBlocklist = "domains_on_blocklist"
        case uniqueClients = "unique_clients"
        case queriesCached = "queries_cached"
        case queriesForwarded = "queries_forwarded"
    }
}

struct InstanceSummary: Codable, Identifiable {
    let id: String
    let name: String
    let url: String
    let color: String?
    let isMaster: Bool
    let isActive: Bool
    let lastSeenAt: Date?
    let status: String
    let dnsQueriesToday: Int
    let queriesBlocked: Int
    let percentBlocked: Double
    let uniqueClients: Int
    let domainsOnBlocklist: Int

    enum CodingKeys: String, CodingKey {
        case id, name, url, color, status
        case isMaster = "is_master"
        case isActive = "is_active"
        case lastSeenAt = "last_seen_at"
        case dnsQueriesToday = "dns_queries_today"
        case queriesBlocked = "queries_blocked"
        case percentBlocked = "percent_blocked"
        case uniqueClients = "unique_clients"
        case domainsOnBlocklist = "domains_on_blocklist"
    }
}

// MARK: - History

struct HistoryResponse: Codable {
    let buckets: [HistoryBucket]
    let instanceId: String?

    enum CodingKeys: String, CodingKey {
        case buckets
        case instanceId = "instance_id"
    }
}

struct HistoryBucket: Codable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let queries: Int
    let blocked: Int

    var date: Date { timestamp }
}

// MARK: - Top Stats

struct TopStatsResponse: Codable {
    let topPermitted: [TopDomain]
    let topBlocked: [TopDomain]
    let topClients: [TopClient]
    let instanceId: String?

    enum CodingKeys: String, CodingKey {
        case topPermitted = "top_permitted"
        case topBlocked = "top_blocked"
        case topClients = "top_clients"
        case instanceId = "instance_id"
    }
}

struct TopDomain: Codable, Identifiable {
    var id: String { domain }
    let domain: String
    let count: Int
}

struct TopClient: Codable, Identifiable {
    var id: String { client }
    let client: String
    let count: Int
}

// MARK: - Client Summary (drill-down)

struct ClientSummary: Codable, Identifiable {
    let clientIp: String
    let clientName: String
    let totalQueries: Int
    let blockedQueries: Int
    let lastSeen: Date?

    var id: String { clientIp.isEmpty ? clientName : clientIp }

    var displayName: String {
        if !clientName.isEmpty { return clientName }
        return clientIp.isEmpty ? "Unknown" : clientIp
    }

    enum CodingKeys: String, CodingKey {
        case clientIp = "client_ip"
        case clientName = "client_name"
        case totalQueries = "total_queries"
        case blockedQueries = "blocked_queries"
        case lastSeen = "last_seen"
    }
}

// MARK: - Query Log

struct QueryPage: Decodable {
    let items: [QueryEntry]
    let total: Int
    let page: Int
    let pageSize: Int

    var pages: Int {
        guard pageSize > 0 else { return 0 }
        return (total + pageSize - 1) / pageSize
    }

    enum CodingKeys: String, CodingKey {
        case items, total, page
        case pageSize = "page_size"
    }
}

struct QueryEntry: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let domain: String
    let clientIp: String
    let clientName: String?
    let status: String
    let instanceId: String?
    let instanceName: String?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, domain, status
        case clientIp = "client_ip"
        case clientName = "client_name"
        case instanceId = "instance_id"
        case instanceName = "instance_name"
    }

    var date: Date { timestamp }

    var isBlocked: Bool {
        let blocked: Set<String> = [
            "GRAVITY", "REGEX", "BLACKLIST",
            "EXTERNAL_BLOCKED_IP", "EXTERNAL_BLOCKED_NULL", "EXTERNAL_BLOCKED_NXDOMAIN",
            "GRAVITY_CNAME", "REGEX_CNAME", "BLACKLIST_CNAME",
        ]
        return blocked.contains(status)
    }

    var isCached: Bool { status == "CACHE" || status == "CACHE_STALE" }

    var statusColor: String {
        if isBlocked { return "red" }
        if isCached { return "blue" }
        return "green"
    }
}

// MARK: - Sync

/// Result of the last (or in-progress) query-log sync run. The server's sync
/// is global — one run covers every instance — so `completedAt` is the same
/// for every instance, while per-instance success/failure is in `results`.
struct SyncStatus: Codable {
    let status: String            // idle / running / success / error
    let startedAt: Date?
    let completedAt: Date?
    let master: String?
    let results: [InstanceSyncResult]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, master, results, error
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

struct InstanceSyncResult: Codable {
    let name: String
    let status: String            // success / error
    let error: String?
}

// MARK: - Error

struct APIError: Decodable, LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}
