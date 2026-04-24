import Foundation

/// Deterministic-ish synthetic data for demo-mode `Site`s. Figures are sized
/// to look like a small home network running Pi-hole — big enough to
/// populate charts / top lists, small enough to stay plausible. Timestamps
/// are always generated relative to `Date()` so the demo never looks
/// "frozen in time."
///
/// Every function ignores `range` / `filter` / `page` inputs where the
/// synthetic data doesn't meaningfully vary — pagination beyond page 1
/// returns empty, and time-range scaling is kept roughly proportional so
/// switching between "Today" and "7d" still produces a believable chart.
enum DemoData {
    // MARK: - Health

    static func health() -> HealthResponse {
        // Decode from canonical JSON so we don't need a public memberwise
        // init that mutates the server-shaped model for every future field
        // change. Force-try is safe — literal is controlled by this file.
        let json = #"""
        {"version": "v1.4.6-demo", "stats_poll_interval": 30, "queries_poll_interval": 30}
        """#
        return try! JSONDecoder().decode(HealthResponse.self, from: Data(json.utf8))
    }

    // MARK: - Summary

    static func summary(range: TimeRange) -> AggregatedSummary {
        let scale = scaleFactor(for: range)
        let total = Int(12_847 * scale)
        let blocked = Int(2_341 * scale)
        let percent = Double(blocked) / Double(max(total, 1)) * 100.0
        let totals = SummaryStats(
            dnsQueriesToday: total,
            queriesBlocked: blocked,
            percentBlocked: percent,
            domainsOnBlocklist: 746_821,
            uniqueClients: 12,
            queriesCached: Int(4_128 * scale),
            queriesForwarded: Int(5_562 * scale)
        )
        let instances: [InstanceSummary] = [
            InstanceSummary(
                id: "demo-primary",
                name: "Pi-hole (Demo)",
                url: "https://demo.mypi.invalid",
                color: "#2563eb",
                isMaster: true,
                isActive: true,
                lastSeenAt: Date(),
                status: "online",
                dnsQueriesToday: total,
                queriesBlocked: blocked,
                percentBlocked: percent,
                uniqueClients: 12,
                domainsOnBlocklist: 746_821
            )
        ]
        return AggregatedSummary(totals: totals, instances: instances)
    }

    // MARK: - History

    static func history(range: TimeRange) -> HistoryResponse {
        let now = Date()
        let bucketCount: Int
        let step: TimeInterval
        switch range {
        case .minutes15: bucketCount = 15;  step = 60
        case .hour1:     bucketCount = 12;  step = 300
        case .today:     bucketCount = 48;  step = 1800
        case .hours24:   bucketCount = 48;  step = 1800
        case .hours48:   bucketCount = 48;  step = 3600
        case .days7:     bucketCount = 42;  step = 4 * 3600
        case .days30:    bucketCount = 60;  step = 12 * 3600
        }

        // Smooth-ish synthetic shape: rising in the morning, peak afternoon,
        // tapering in the evening. Seeded-ish so the chart doesn't flicker
        // frantically when the VM refreshes.
        let buckets: [HistoryBucket] = (0..<bucketCount).map { idx in
            let t = now.addingTimeInterval(-Double(bucketCount - idx) * step)
            let phase = Double(idx) / Double(bucketCount) * .pi
            let queries = Int(140 + sin(phase) * 80 + Double((idx * 13) % 23))
            let blocked = Int(Double(queries) * 0.18)
            return HistoryBucket(timestamp: t, queries: queries, blocked: blocked)
        }
        return HistoryResponse(buckets: buckets, instanceId: "demo-primary")
    }

    // MARK: - Top

    static func top(range: TimeRange, limit: Int = 10) -> TopStatsResponse {
        let topPermitted: [TopDomain] = [
            ("apple.com",                   1_284),
            ("icloud.com",                    912),
            ("github.com",                    486),
            ("push.apple.com",                421),
            ("ntp.pool.org",                  318),
            ("gateway.icloud.com",            302),
            ("cdn-apple.com",                 274),
            ("weather.apple.com",             219),
            ("news.ycombinator.com",          187),
            ("spotify.com",                   166),
        ].prefix(limit).map { TopDomain(domain: $0.0, count: $0.1) }

        let topBlocked: [TopDomain] = [
            ("doubleclick.net",               612),
            ("google-analytics.com",          468),
            ("graph.facebook.com",            331),
            ("api.mixpanel.com",              284),
            ("ads.youtube.com",               221),
            ("app-measurement.com",           203),
            ("telemetry.microsoft.com",       198),
            ("ads-api.twitter.com",           156),
            ("collector.newrelic.com",        121),
            ("tr.snapchat.com",                98),
        ].prefix(limit).map { TopDomain(domain: $0.0, count: $0.1) }

        let topClients: [TopClient] = [
            ("Living-Room-TV (10.0.1.50)",  4_612),
            ("iPhone-15-Pro (10.0.1.20)",   3_188),
            ("Kitchen-iPad (10.0.1.30)",    1_942),
            ("MacBook-Air (10.0.1.15)",     1_218),
            ("Kids-iPad (10.0.1.40)",         762),
            ("Office-MacBook (10.0.1.12)",    517),
            ("Thermostat (10.0.1.60)",        284),
            ("Doorbell (10.0.1.61)",          203),
            ("Sonos-Living (10.0.1.70)",      174),
            ("Switch (10.0.1.80)",            108),
        ].prefix(limit).map { TopClient(client: $0.0, count: $0.1) }

        return TopStatsResponse(
            topPermitted: topPermitted,
            topBlocked: topBlocked,
            topClients: topClients,
            instanceId: "demo-primary"
        )
    }

    // MARK: - Query log

    static func queries(page: Int, pageSize: Int, range: TimeRange, filter: QueryFilter, domain: String?) -> QueryPage {
        // Only page 1 has content — pagination in demo mode just stops.
        let total = page == 1 ? 120 : 0
        let items = page == 1 ? syntheticQueries(count: min(pageSize, total), filter: filter) : []
        return QueryPage(items: items, total: total, page: page, pageSize: pageSize)
    }

    static func clients(range: TimeRange) -> [ClientSummary] {
        let rows: [(String, String, Int, Int, TimeInterval)] = [
            ("10.0.1.50", "Living-Room-TV",  4_612, 842,  60),
            ("10.0.1.20", "iPhone-15-Pro",   3_188, 512, 120),
            ("10.0.1.30", "Kitchen-iPad",    1_942, 338, 180),
            ("10.0.1.15", "MacBook-Air",     1_218, 221, 240),
            ("10.0.1.40", "Kids-iPad",         762,  98, 300),
            ("10.0.1.12", "Office-MacBook",    517,  84, 360),
            ("10.0.1.60", "Thermostat",        284,  12, 600),
            ("10.0.1.61", "Doorbell",          203,  18, 720),
            ("10.0.1.70", "Sonos-Living",      174,   9, 900),
            ("10.0.1.80", "Switch",            108,   4, 1200),
            ("10.0.1.90", "Printer",            54,   2, 1800),
            ("10.0.1.99", "Guest-Laptop",       18,   6, 3600),
        ]
        let now = Date()
        return rows.map { row in
            ClientSummary(
                clientIp: row.0,
                clientName: row.1,
                totalQueries: row.2,
                blockedQueries: row.3,
                lastSeen: now.addingTimeInterval(-row.4)
            )
        }
    }

    // MARK: - Sync

    static func syncStatus() -> SyncStatus {
        let now = Date()
        return SyncStatus(
            status: "success",
            startedAt: now.addingTimeInterval(-61),
            completedAt: now.addingTimeInterval(-60),
            master: "Pi-hole (Demo)",
            results: [
                InstanceSyncResult(name: "Pi-hole (Demo)", status: "success", error: nil)
            ],
            error: nil
        )
    }

    // MARK: - Helpers

    private static func scaleFactor(for range: TimeRange) -> Double {
        switch range {
        case .minutes15: return 0.05
        case .hour1:     return 0.15
        case .today:     return 1.0
        case .hours24:   return 1.0
        case .hours48:   return 1.9
        case .days7:     return 6.6
        case .days30:    return 27.2
        }
    }

    private static func syntheticQueries(count: Int, filter: QueryFilter) -> [QueryEntry] {
        let domains = [
            "apple.com",           "icloud.com",
            "github.com",          "spotify.com",
            "doubleclick.net",     "google-analytics.com",
            "graph.facebook.com",  "api.mixpanel.com",
            "ads.youtube.com",     "ntp.pool.org",
            "push.apple.com",      "news.ycombinator.com",
            "weather.apple.com",   "cdn-apple.com",
            "telemetry.microsoft.com",
        ]
        let clients: [(String, String)] = [
            ("10.0.1.50", "Living-Room-TV"),
            ("10.0.1.20", "iPhone-15-Pro"),
            ("10.0.1.30", "Kitchen-iPad"),
            ("10.0.1.15", "MacBook-Air"),
            ("10.0.1.40", "Kids-iPad"),
        ]
        let statuses = ["OK", "OK", "OK", "CACHE", "GRAVITY", "REGEX", "OK", "FORWARDED"]
        let now = Date()
        var out: [QueryEntry] = []
        for i in 0..<count {
            let domain = domains[i % domains.count]
            let client = clients[i % clients.count]
            let rawStatus = statuses[(i * 7) % statuses.count]
            // Respect filter so "Blocked" / "Permitted" chips feel live.
            let status: String = {
                switch filter {
                case .blocked:
                    return ["GRAVITY", "REGEX", "BLACKLIST"][i % 3]
                case .permitted:
                    return ["OK", "CACHE", "FORWARDED"][i % 3]
                default:
                    return rawStatus
                }
            }()
            out.append(QueryEntry(
                id: "demo-\(i)",
                timestamp: now.addingTimeInterval(-Double(i) * 17),
                domain: domain,
                clientIp: client.0,
                clientName: client.1,
                status: status,
                instanceId: "demo-primary",
                instanceName: "Pi-hole (Demo)"
            ))
        }
        return out
    }
}
