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

struct QueryEntry: Codable, Identifiable, Hashable {
    let id: String
    let timestamp: Date
    let domain: String
    let clientIp: String
    let clientName: String?
    let status: String
    let instanceId: String?
    let instanceName: String?
    /// DNS record type asked for (A, AAAA, HTTPS, PTR, …).
    let queryType: String?
    /// How the resolver answered (IP, CNAME, NODATA, NXDOMAIN, …).
    let replyType: String?
    /// Time Pi-hole took to answer, in milliseconds.
    let replyTimeMs: Double?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, domain, status
        case clientIp = "client_ip"
        case clientName = "client_name"
        case instanceId = "instance_id"
        case instanceName = "instance_name"
        case queryType = "query_type"
        case replyType = "reply_type"
        case replyTimeMs = "reply_time_ms"
    }

    var date: Date { timestamp }

    var statusKind: QueryStatusKind { QueryStatusKind(status: status) }
    var isBlocked: Bool { statusKind == .blocked }
    var isCached: Bool { statusKind == .cached }

    /// Best label for the requesting device: its name when Pi-hole resolved
    /// one, else the IP, else a placeholder.
    var clientDisplayName: String {
        if let name = clientName, !name.isEmpty { return name }
        return clientIp.isEmpty ? "Unknown client" : clientIp
    }

    var statusColor: String {
        switch statusKind {
        case .blocked: return "red"
        case .cached: return "blue"
        case .permitted, .other: return "green"
        }
    }
}

extension QueryEntry {
    /// Tolerant decoder. The server's schema marks `domain`, `client_ip`,
    /// `status` and the reply fields as nullable (a row Pi-hole reported
    /// without them is stored as NULL), and a synthesized decoder would fail
    /// the *whole page* on a single such row. Missing text decodes as "" and
    /// the detail fields as nil. Lives in an extension so the memberwise
    /// initializer (used by `DemoData`) is kept.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
        clientIp = try c.decodeIfPresent(String.self, forKey: .clientIp) ?? ""
        clientName = try c.decodeIfPresent(String.self, forKey: .clientName)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        instanceId = try c.decodeIfPresent(String.self, forKey: .instanceId)
        instanceName = try c.decodeIfPresent(String.self, forKey: .instanceName)
        queryType = try c.decodeIfPresent(String.self, forKey: .queryType)
        replyType = try c.decodeIfPresent(String.self, forKey: .replyType)
        replyTimeMs = try c.decodeIfPresent(Double.self, forKey: .replyTimeMs)
    }
}

/// Coarse classification of a Pi-hole query status, driving the row icon,
/// the detail header and the legend.
enum QueryStatusKind: Equatable {
    case blocked, cached, permitted, other

    /// Statuses the MyPi server counts as blocked (`BLOCKED_STATUSES` in the
    /// server's `app/api/stats.py`), plus the names Pi-hole v6 uses for the
    /// same outcomes (`DENYLIST*` replaced `BLACKLIST*`; `…_NXRA` /
    /// `…_EDE15` are the upstream-blocked variants) so a row is never drawn
    /// as permitted just because the status string was renamed.
    static let blockedStatuses: Set<String> = [
        "GRAVITY", "REGEX", "BLACKLIST",
        "EXTERNAL_BLOCKED_IP", "EXTERNAL_BLOCKED_NULL", "EXTERNAL_BLOCKED_NXDOMAIN",
        "GRAVITY_CNAME", "REGEX_CNAME", "BLACKLIST_CNAME",
        "DENYLIST", "DENYLIST_CNAME",
        "EXTERNAL_BLOCKED_NXRA", "EXTERNAL_BLOCKED_EDE15",
        "SPECIAL_DOMAIN",
    ]

    static let permittedStatuses: Set<String> = [
        "FORWARDED", "RETRIED", "RETRIED_DNSSEC", "OK",
    ]

    init(status: String) {
        let s = status.uppercased()
        if Self.blockedStatuses.contains(s) {
            self = .blocked
        } else if s == "CACHE" || s == "CACHE_STALE" {
            self = .cached
        } else if Self.permittedStatuses.contains(s) {
            self = .permitted
        } else {
            self = .other
        }
    }

    var title: String {
        switch self {
        case .blocked: return "Blocked"
        case .cached: return "Cached"
        case .permitted: return "Permitted"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .blocked: return "shield.fill"
        case .cached: return "memorychip"
        case .permitted: return "checkmark.circle.fill"
        case .other: return "questionmark.circle"
        }
    }
}

/// Plain-English explanations of the raw Pi-hole strings shown in the query
/// detail screen. Unknown values fall through to nil and the raw value is
/// shown on its own.
enum QueryGlossary {
    static func statusExplanation(_ status: String) -> String? {
        switch status.uppercased() {
        case "GRAVITY": return "Blocked: the domain is on one of your adlists."
        case "GRAVITY_CNAME": return "Blocked: a CNAME in the answer chain is on one of your adlists."
        case "REGEX": return "Blocked by a regex deny rule."
        case "REGEX_CNAME": return "Blocked: a CNAME in the answer chain matched a regex deny rule."
        case "BLACKLIST", "DENYLIST": return "Blocked by an exact entry on the deny list."
        case "BLACKLIST_CNAME", "DENYLIST_CNAME": return "Blocked: a CNAME in the answer chain is on the deny list."
        case "EXTERNAL_BLOCKED_IP": return "Blocked upstream: the resolver answered with a known blocking address."
        case "EXTERNAL_BLOCKED_NULL": return "Blocked upstream: the resolver answered with a null address."
        case "EXTERNAL_BLOCKED_NXDOMAIN", "EXTERNAL_BLOCKED_NXRA": return "Blocked upstream: the resolver answered that the domain doesn't exist."
        case "EXTERNAL_BLOCKED_EDE15": return "Blocked upstream: the resolver reported the answer as blocked."
        case "SPECIAL_DOMAIN": return "Handled by Pi-hole itself as a special-purpose domain."
        case "FORWARDED": return "Permitted and forwarded to the upstream resolver."
        case "CACHE": return "Permitted and answered from Pi-hole's cache."
        case "CACHE_STALE": return "Permitted and answered from an expired cache entry while it refreshed."
        case "RETRIED": return "Permitted; the upstream query was retried."
        case "RETRIED_DNSSEC": return "Permitted; retried for DNSSEC validation."
        case "IN_PROGRESS": return "Still waiting for an upstream answer when this was recorded."
        case "DBBUSY": return "Pi-hole's database was busy, so the query couldn't be evaluated."
        case "UNKNOWN", "": return "Pi-hole didn't report a status for this query."
        default: return nil
        }
    }

    static func queryTypeExplanation(_ type: String) -> String? {
        switch type.uppercased() {
        case "A": return "IPv4 address"
        case "AAAA": return "IPv6 address"
        case "ANY": return "Any record"
        case "SRV": return "Service locator"
        case "SOA": return "Zone authority"
        case "PTR": return "Reverse lookup"
        case "TXT": return "Text record"
        case "NAPTR": return "Name authority pointer"
        case "MX": return "Mail server"
        case "DS": return "DNSSEC delegation signer"
        case "RRSIG": return "DNSSEC signature"
        case "DNSKEY": return "DNSSEC key"
        case "NS": return "Name server"
        case "SVCB": return "Service binding"
        case "HTTPS": return "HTTPS service binding"
        case "CNAME": return "Alias"
        default: return nil
        }
    }

    static func replyTypeExplanation(_ type: String) -> String? {
        switch type.uppercased() {
        case "IP": return "An address was returned"
        case "CNAME": return "An alias was returned"
        case "NODATA": return "The domain exists but has no record of this type"
        case "NXDOMAIN": return "The domain doesn't exist"
        case "DOMAIN": return "A domain name was returned"
        case "RRNAME": return "A resource-record name was returned"
        case "SERVFAIL": return "The upstream resolver failed"
        case "REFUSED": return "The upstream resolver refused the query"
        case "NOTIMP": return "The upstream resolver doesn't implement this query"
        case "DNSSEC": return "DNSSEC data was returned"
        case "BLOB": return "Binary data was returned"
        case "NONE": return "No reply was sent"
        case "OTHER": return "Another kind of record was returned"
        case "UNKNOWN": return "No reply was recorded"
        default: return nil
        }
    }
}

// MARK: - Domain lists

/// Allow/deny-list membership for one domain (`/api/domains/status/{domain}`),
/// read live from the site's master Pi-hole.
struct DomainListStatus: Decodable, Equatable {
    let domain: String
    let inDeny: Bool
    let inAllow: Bool
    /// "allowed" (allow entry wins), "denied", or "unmanaged".
    let effective: String

    enum CodingKeys: String, CodingKey {
        case domain, effective
        case inDeny = "in_deny"
        case inAllow = "in_allow"
    }
}

/// Which list(s) block a domain (`/api/domains/blocklists/{domain}`, MyPi
/// server 2.6.0+), plus how often it was gravity-blocked in the window.
struct DomainBlocklists: Decodable, Equatable {
    let domain: String
    let blockCount: Int
    let lists: [Entry]

    struct Entry: Decodable, Equatable, Identifiable {
        let name: String
        let address: String?
        /// "gravity", "deny-exact" or "deny-regex".
        let kind: String
        let enabled: Bool
        let isSecurity: Bool

        var id: String { "\(kind)|\(name)|\(address ?? "")" }

        var kindLabel: String {
            switch kind {
            case "gravity": return "Adlist"
            case "deny-exact": return "Deny list (exact)"
            case "deny-regex": return "Deny list (regex)"
            default: return kind
            }
        }

        enum CodingKeys: String, CodingKey {
            case name, address, kind, enabled
            case isSecurity = "is_security"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            address = try c.decodeIfPresent(String.self, forKey: .address)
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            isSecurity = try c.decodeIfPresent(Bool.self, forKey: .isSecurity) ?? false
        }

        init(name: String, address: String?, kind: String, enabled: Bool = true, isSecurity: Bool = false) {
            self.name = name
            self.address = address
            self.kind = kind
            self.enabled = enabled
            self.isSecurity = isSecurity
        }
    }

    enum CodingKeys: String, CodingKey {
        case domain, lists
        case blockCount = "block_count"
    }

    init(domain: String, blockCount: Int, lists: [Entry]) {
        self.domain = domain
        self.blockCount = blockCount
        self.lists = lists
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        domain = try c.decode(String.self, forKey: .domain)
        blockCount = try c.decodeIfPresent(Int.self, forKey: .blockCount) ?? 0
        lists = try c.decodeIfPresent([Entry].self, forKey: .lists) ?? []
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
