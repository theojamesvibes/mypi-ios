import Foundation

/// HTTP client for a single MyPi site. Holds a persistent URLSession configured
/// for the site's TLS policy. API key is fetched from the Keychain on each request.
final class APIClient {
    let site: Site

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
    }

    // MARK: - Public endpoints

    func health() async throws -> HealthResponse {
        try await get("/api/health", authenticated: false)
    }

    func summary(hours: Int = 24) async throws -> AggregatedSummary {
        try await get("/api/stats/summary?hours=\(hours)")
    }

    func history(hours: Int = 24, bucketMinutes: Int = 10) async throws -> HistoryResponse {
        try await get("/api/stats/history?hours=\(hours)&bucket_minutes=\(bucketMinutes)")
    }

    func top(hours: Int = 24, limit: Int = 10) async throws -> TopStatsResponse {
        try await get("/api/stats/top?hours=\(hours)&limit=\(limit)")
    }

    func queries(page: Int = 1, pageSize: Int = 50, hours: Int = 24, filter: QueryFilter = .all) async throws -> QueryPage {
        var path = "/api/queries?page=\(page)&page_size=\(pageSize)&hours=\(hours)"
        if let type_ = filter.queryType { path += "&query_type=\(type_)" }
        return try await get(path)
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
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - QueryFilter

enum QueryFilter: String, CaseIterable, Identifiable {
    case all, permitted, blocked, cached

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .permitted: return "Permitted"
        case .blocked: return "Blocked"
        case .cached: return "Cached"
        }
    }

    var queryType: String? {
        switch self {
        case .all: return nil
        case .permitted: return "permitted"
        case .blocked: return "blocked"
        case .cached: return "cached"
        }
    }
}
