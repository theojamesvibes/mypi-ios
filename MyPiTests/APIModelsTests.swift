import Foundation
import Testing
@testable import MyPi

// MARK: - Date parsing
//
// APIClient.parseDate is the heart of the decode robustness that previous releases
// got wrong (see CHANGELOG 0.0.5 "fix Query Log decode … missing data"). The MyPi
// server (FastAPI) emits datetimes with microsecond precision and sometimes without
// a timezone designator, so several shapes must all parse.

struct DateParsingTests {
    @Test func naiveTimestampIsInterpretedAsUTC() throws {
        // A timezone-less timestamp must resolve to the same instant as the same
        // wall-clock time with an explicit Z — i.e. it is treated as UTC, not local.
        let naive = try #require(APIClient.parseDate("2026-05-25T12:30:45"))
        let withZ = try #require(APIClient.parseDate("2026-05-25T12:30:45Z"))
        #expect(naive == withZ)
    }

    @Test func fractionalNaiveTimestampParses() throws {
        let whole = try #require(APIClient.parseDate("2026-05-25T12:30:45"))
        let frac = try #require(APIClient.parseDate("2026-05-25T12:30:45.250000"))
        // Lands within the same second, after the whole-second mark.
        let delta = frac.timeIntervalSince(whole)
        #expect(delta >= 0)
        #expect(delta < 1)
    }

    @Test func iso8601WithFractionAndZoneParses() {
        #expect(APIClient.parseDate("2026-05-25T12:30:45.123Z") != nil)
    }

    @Test func unparseableStringsReturnNil() {
        #expect(APIClient.parseDate("not-a-date") == nil)
        #expect(APIClient.parseDate("") == nil)
        #expect(APIClient.parseDate("25/05/2026") == nil)
    }
}

// MARK: - Query Log decoding

struct QueryLogDecodingTests {
    @Test func decodesPageWithSnakeCaseAndOptionalFields() throws {
        let json = """
        {
          "items": [
            {"id":"1","timestamp":"2026-05-25T12:30:45","domain":"ads.example.com",
             "client_ip":"192.168.1.5","client_name":"laptop","status":"GRAVITY",
             "instance_id":"pi1","instance_name":"Pi One"},
            {"id":"2","timestamp":"2026-05-25T12:31:00.250000","domain":"ok.example.com",
             "client_ip":"192.168.1.6","client_name":null,"status":"FORWARDED",
             "instance_id":null,"instance_name":null}
          ],
          "total": 42,
          "page": 1,
          "page_size": 20
        }
        """
        let page = try makeAPIDecoder().decode(QueryPage.self, from: Data(json.utf8))

        #expect(page.items.count == 2)
        #expect(page.total == 42)
        #expect(page.pageSize == 20)
        #expect(page.pages == 3) // ceil(42 / 20)

        let blocked = page.items[0]
        #expect(blocked.clientName == "laptop")
        #expect(blocked.instanceName == "Pi One")
        #expect(blocked.isBlocked)
        #expect(blocked.statusColor == "red")

        // The regression that motivated these tests: optional fields arriving as
        // null / absent must decode to nil rather than failing the whole page.
        let forwarded = page.items[1]
        #expect(forwarded.clientName == nil)
        #expect(forwarded.instanceId == nil)
        #expect(forwarded.instanceName == nil)
        #expect(!forwarded.isBlocked)
        #expect(forwarded.statusColor == "green")
    }

    @Test func classifiesPiholeStatusValues() throws {
        func entry(_ status: String) throws -> QueryEntry {
            let json = """
            {"id":"x","timestamp":"2026-05-25T00:00:00","domain":"d",
             "client_ip":"1.2.3.4","status":"\(status)"}
            """
            return try makeAPIDecoder().decode(QueryEntry.self, from: Data(json.utf8))
        }
        #expect(try entry("GRAVITY").isBlocked)
        #expect(try entry("REGEX_CNAME").isBlocked)
        #expect(try entry("BLACKLIST").isBlocked)
        #expect(try entry("CACHE").isCached)
        #expect(try entry("CACHE_STALE").isCached)
        #expect(try entry("FORWARDED").statusColor == "green")
        #expect(try entry("CACHE").statusColor == "blue")
        #expect(try entry("GRAVITY").statusColor == "red")
    }

    @Test func unparseableTimestampThrows() {
        let json = #"{"id":"x","timestamp":"25/05/2026","domain":"d","client_ip":"1.2.3.4","status":"FORWARDED"}"#
        #expect(throws: (any Error).self) {
            try makeAPIDecoder().decode(QueryEntry.self, from: Data(json.utf8))
        }
    }

    @Test func pageCountHandlesEmptyAndExactMultiples() throws {
        func page(total: Int, size: Int) throws -> QueryPage {
            let json = #"{"items":[],"total":\#(total),"page":1,"page_size":\#(size)}"#
            return try makeAPIDecoder().decode(QueryPage.self, from: Data(json.utf8))
        }
        #expect(try page(total: 0, size: 20).pages == 0)
        #expect(try page(total: 40, size: 20).pages == 2)
        #expect(try page(total: 41, size: 20).pages == 3)
        #expect(try page(total: 10, size: 0).pages == 0) // guard against /0
    }
}

// MARK: - Dashboard decoding

struct DashboardDecodingTests {
    @Test func decodesAggregatedSummary() throws {
        let json = """
        {
          "totals": {"dns_queries_today":1000,"queries_blocked":250,"percent_blocked":25.0,
                     "domains_on_blocklist":50000,"unique_clients":12,
                     "queries_cached":300,"queries_forwarded":450},
          "instances": [
            {"id":"pi1","name":"Pi One","url":"https://pi.one","color":"#ffffff",
             "is_master":true,"is_active":true,"last_seen_at":"2026-05-25T12:30:45",
             "status":"online","dns_queries_today":1000,"queries_blocked":250,
             "percent_blocked":25.0,"unique_clients":12,"domains_on_blocklist":50000}
          ]
        }
        """
        let summary = try makeAPIDecoder().decode(AggregatedSummary.self, from: Data(json.utf8))
        #expect(summary.totals.dnsQueriesToday == 1000)
        #expect(summary.totals.queriesForwarded == 450)
        #expect(summary.totals.percentBlocked == 25.0)
        #expect(summary.instances.count == 1)
        #expect(summary.instances[0].isMaster)
        #expect(summary.instances[0].color == "#ffffff")
        #expect(summary.instances[0].lastSeenAt != nil)
    }

    @Test func instanceNullOptionalsDecodeToNil() throws {
        let json = """
        {
          "totals": {"dns_queries_today":0,"queries_blocked":0,"percent_blocked":0.0,
                     "domains_on_blocklist":0,"unique_clients":0,
                     "queries_cached":0,"queries_forwarded":0},
          "instances": [
            {"id":"pi2","name":"Pi Two","url":"https://pi.two","color":null,
             "is_master":false,"is_active":false,"last_seen_at":null,"status":"offline",
             "dns_queries_today":0,"queries_blocked":0,"percent_blocked":0.0,
             "unique_clients":0,"domains_on_blocklist":0}
          ]
        }
        """
        let summary = try makeAPIDecoder().decode(AggregatedSummary.self, from: Data(json.utf8))
        let inst = summary.instances[0]
        #expect(inst.color == nil)
        #expect(inst.lastSeenAt == nil)
        #expect(inst.isMaster == false)
    }

    @Test func decodesHistory() throws {
        let json = """
        {"buckets":[{"timestamp":"2026-05-25T12:00:00","queries":10,"blocked":2}],"instance_id":null}
        """
        let history = try makeAPIDecoder().decode(HistoryResponse.self, from: Data(json.utf8))
        #expect(history.buckets.count == 1)
        #expect(history.buckets[0].queries == 10)
        #expect(history.buckets[0].blocked == 2)
        #expect(history.instanceId == nil)
        #expect(history.buckets[0].id == history.buckets[0].timestamp)
    }

    @Test func clientSummaryDisplayNameAndId() throws {
        func client(ip: String, name: String) throws -> ClientSummary {
            let json = """
            {"client_ip":"\(ip)","client_name":"\(name)","total_queries":5,
             "blocked_queries":1,"last_seen":null}
            """
            return try makeAPIDecoder().decode(ClientSummary.self, from: Data(json.utf8))
        }
        #expect(try client(ip: "192.168.1.5", name: "TV").displayName == "TV")
        #expect(try client(ip: "192.168.1.5", name: "").displayName == "192.168.1.5")
        #expect(try client(ip: "", name: "").displayName == "Unknown")
        #expect(try client(ip: "192.168.1.5", name: "").id == "192.168.1.5")
        #expect(try client(ip: "", name: "TV").id == "TV")
    }
}
