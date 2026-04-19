import Foundation
import Observation

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
        d.dateDecodingStrategy = .iso8601
        return d
    }()

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

    // MARK: - Public endpoints

    func health() async throws -> HealthResponse {
        try await get("/api/health", authenticated: false)
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
        try await get("/api/stats/summary?\(range.queryString())")
    }

    func history(range: TimeRange) async throws -> HistoryResponse {
        try await get("/api/stats/history?\(range.queryString())&bucket_minutes=\(range.bucketMinutes)")
    }

    func top(range: TimeRange, limit: Int = 10) async throws -> TopStatsResponse {
        try await get("/api/stats/top?\(range.queryString())&limit=\(limit)")
    }

    func queries(page: Int = 1, pageSize: Int = 50, range: TimeRange, filter: QueryFilter = .all) async throws -> QueryPage {
        var path = "/api/queries?page=\(page)&page_size=\(pageSize)&\(range.queryString())"
        if let q = filter.queryParam { path += "&\(q)" }
        return try await get(path)
    }

    /// Raw blocked-only rows, timestamp DESC. Used by the Blocked drill-down to
    /// compute the latest block per domain via client-side dedupe.
    func blockedQueries(range: TimeRange, pageSize: Int = 500) async throws -> QueryPage {
        try await get("/api/queries?page=1&page_size=\(pageSize)&blocked=true&\(range.queryString())")
    }

    /// Aggregated per-client stats, grouped server-side. Used by the Unique Clients drill-down.
    func clients(range: TimeRange) async throws -> [ClientSummary] {
        try await get("/api/queries/clients?\(range.queryString())")
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

/// Matches the filter options the MyPi server `/api/queries` endpoint supports.
/// The server exposes a `blocked: bool` query param; there is no dedicated
/// "cached" filter, so we don't expose one here.
enum QueryFilter: String, CaseIterable, Identifiable {
    case all, permitted, blocked

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .permitted: return "Permitted"
        case .blocked: return "Blocked"
        }
    }

    /// Raw query-string fragment to append, or nil for no filter.
    var queryParam: String? {
        switch self {
        case .all: return nil
        case .permitted: return "blocked=false"
        case .blocked: return "blocked=true"
        }
    }
}
