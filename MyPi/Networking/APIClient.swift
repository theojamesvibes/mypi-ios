import Foundation
import Observation

private let _isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let _isoBasic: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let _naiveFractional: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
    return f
}()

private let _naiveBasic: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f
}()

/// HTTP client for a single MyPi site. Holds a persistent URLSession configured
/// for the site's TLS policy. API key is fetched from the Keychain on each request.
@Observable
final class APIClient {
    let site: Site

    /// Negotiated TLS protocol version observed on the most recent request
    /// (e.g. "TLS 1.3"). `nil` until the first request completes.
    private(set) var lastTLSVersion: String?

    private let session: URLSession
    private let tlsDelegate: TLSDelegate
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // FastAPI on the server emits datetimes with microsecond precision
        // and sometimes without a timezone designator; the default .iso8601
        // strategy rejects both shapes, so we try a sequence of parsers.
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = APIClient.parseDate(str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(str)"
            )
        }
        return d
    }()

    /// Try a sequence of ISO 8601 shapes; returns nil if none match.
    static func parseDate(_ s: String) -> Date? {
        if let d = _isoFractional.date(from: s) { return d }
        if let d = _isoBasic.date(from: s) { return d }
        if let d = _naiveFractional.date(from: s) { return d }
        if let d = _naiveBasic.date(from: s) { return d }
        return nil
    }

    /// Fires when an unrecognised certificate is encountered (TOFU opportunity).
    var onUntrustedCertificate: ((String) -> Void)? {
        get { tlsDelegate.onUntrustedCertificate }
        set { tlsDelegate.onUntrustedCertificate = newValue }
    }

    init(site: Site) {
        self.site = site
        self.tlsDelegate = TLSDelegate(
            allowSelfSigned: site.allowSelfSigned,
            pinnedFingerprint: site.pinnedCertFingerprint
        )
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config, delegate: tlsDelegate, delegateQueue: nil)
        self.tlsDelegate.onTLSVersionObserved = { [weak self] version in
            Task { @MainActor in self?.lastTLSVersion = version }
        }
    }

    /// `URLSession` retains its delegate strongly, so without an explicit
    /// invalidate the session + TLSDelegate pair leaks for the app's lifetime
    /// every time an `APIClient` is replaced (e.g. after a site edit).
    deinit {
        session.finishTasksAndInvalidate()
    }

    // MARK: - Public endpoints

    func health() async throws -> HealthResponse {
        if site.isDemo { return DemoData.health() }
        return try await get("/api/health", authenticated: false)
    }

    /// Verify a candidate API key against an authenticated endpoint without
    /// having to persist it to the Keychain first. Throws `APIError` on 401.
    func verifyAPIKey(_ key: String) async throws {
        guard let url = URL(string: "/api/stats/summary?hours=1", relativeTo: site.baseURL)?.absoluteURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let apiErr = try? decoder.decode(APIError.self, from: data) {
                throw apiErr
            }
            throw URLError(.badServerResponse)
        }
    }

    func summary(range: TimeRange) async throws -> AggregatedSummary {
        if site.isDemo { return DemoData.summary(range: range) }
        return try await get("/api/stats/summary?\(range.queryString())")
    }

    func history(range: TimeRange) async throws -> HistoryResponse {
        if site.isDemo { return DemoData.history(range: range) }
        return try await get("/api/stats/history?\(range.queryString())&bucket_minutes=\(range.bucketMinutes)")
    }

    func top(range: TimeRange, limit: Int = 10) async throws -> TopStatsResponse {
        if site.isDemo { return DemoData.top(range: range, limit: limit) }
        return try await get("/api/stats/top?\(range.queryString())&limit=\(limit)")
    }

    func queries(page: Int = 1, pageSize: Int = 50, range: TimeRange, filter: QueryFilter = .all, domain: String? = nil) async throws -> QueryPage {
        if site.isDemo {
            return DemoData.queries(page: page, pageSize: pageSize, range: range, filter: filter, domain: domain)
        }
        var path = "/api/queries?page=\(page)&page_size=\(pageSize)&\(range.queryString())"
        if let q = filter.queryParam { path += "&\(q)" }
        if let d = domain?.trimmingCharacters(in: .whitespaces), !d.isEmpty,
           let encoded = d.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&domain=\(encoded)"
        }
        return try await get(path)
    }

    /// Aggregated per-client stats, grouped server-side. Used by the Unique Clients drill-down.
    func clients(range: TimeRange) async throws -> [ClientSummary] {
        if site.isDemo { return DemoData.clients(range: range) }
        return try await get("/api/queries/clients?\(range.queryString())")
    }

    /// Global sync state — the timestamp of the last query-log sync run,
    /// plus per-instance success/failure. The sync schedule runs hourly by
    /// default (separate from the stats poll which is much more frequent).
    func syncStatus() async throws -> SyncStatus {
        if site.isDemo { return DemoData.syncStatus() }
        return try await get("/api/sync/status")
    }

    // MARK: - Generic request

    func get<T: Decodable>(_ path: String, authenticated: Bool = true) async throws -> T {
        guard let url = URL(string: path, relativeTo: site.baseURL)?.absoluteURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if authenticated {
            if let key = KeychainStore.shared.apiKey(for: site.id) {
                request.setValue(key, forHTTPHeaderField: "X-API-Key")
            }
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let apiErr = try? decoder.decode(APIError.self, from: data) {
                throw apiErr
            }
            if http.statusCode == 401 {
                throw APIError(detail: "Not authenticated")
            }
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - QueryFilter

/// Mirrors the Filter dropdown on the MyPi web Query Log:
/// All / Permitted / Blocked map to `/api/queries?blocked=...`, while
/// `.uniqueClients` swaps the list for the server's per-client aggregate
/// from `/api/queries/clients`.
enum QueryFilter: String, CaseIterable, Identifiable {
    case all, permitted, blocked, uniqueClients

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .permitted: return "Permitted"
        case .blocked: return "Blocked"
        case .uniqueClients: return "Unique Clients"
        }
    }

    /// Raw query-string fragment for /api/queries; returns nil for All and
    /// for Unique Clients (which hits a different endpoint entirely).
    var queryParam: String? {
        switch self {
        case .all, .uniqueClients: return nil
        case .permitted: return "blocked=false"
        case .blocked: return "blocked=true"
        }
    }

    var isClientsMode: Bool { self == .uniqueClients }
}
