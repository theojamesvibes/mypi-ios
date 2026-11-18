import Foundation
import Observation

// `ISO8601DateFormatter` is documented thread-safe but isn't annotated
// `Sendable`; these are configured once and never mutated afterwards.
nonisolated(unsafe) private let _isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

nonisolated(unsafe) private let _isoBasic: ISO8601DateFormatter = {
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
///
/// `@unchecked Sendable`: requests are issued from the main-actor view models
/// but run (and decode) off the main thread. Everything here is immutable
/// after `init` except `lastTLSVersion`, which is only ever written on the
/// main actor, and the TOFU handler, which `TLSDelegate` guards with a lock.
@Observable
final class APIClient: @unchecked Sendable {
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
    private var onUntrustedCertificate: (@Sendable (String) -> Void)? {
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

    /// TOFU probe: issue the unauthenticated health request with a capture
    /// handler attached and return the leaf-certificate fingerprint the
    /// server presented, or nil when the connection validated without the
    /// self-signed path. The handler is detached again before returning, so
    /// this client goes back to failing closed and can't later send the API
    /// key over a connection nobody has approved.
    func probeCertificateFingerprint() async throws -> String? {
        let box = FingerprintBox()
        onUntrustedCertificate = { box.set($0) }
        defer { onUntrustedCertificate = nil }
        _ = try await health()
        return box.value
    }

    /// Discover the backend sites a multi-site MyPi server (1.11+) hosts.
    /// Single-site / legacy servers don't expose this endpoint — callers
    /// should treat any error as "single-site server" rather than a hard
    /// failure (404 on legacy, 200 with one row on single-site multisite).
    func mypiSites() async throws -> [MyPiSite] {
        if site.isDemo { return DemoData.mypiSites() }
        return try await get("/api/sites")
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

    func history(range: TimeRange, instanceId: String? = nil) async throws -> HistoryResponse {
        if site.isDemo { return DemoData.history(range: range, instanceId: instanceId) }
        var path = "/api/stats/history?\(range.queryString())&bucket_minutes=\(range.bucketMinutes)"
        if let inst = Self.queryValue(instanceId) { path += "&instance_id=\(inst)" }
        return try await get(path)
    }

    func top(range: TimeRange, limit: Int = 10) async throws -> TopStatsResponse {
        if site.isDemo { return DemoData.top(range: range, limit: limit) }
        return try await get("/api/stats/top?\(range.queryString())&limit=\(limit)")
    }

    func queries(
        page: Int = 1,
        pageSize: Int = 50,
        range: TimeRange,
        filter: QueryFilter = .all,
        domain: String? = nil,
        client: String? = nil,
        instanceId: String? = nil
    ) async throws -> QueryPage {
        if site.isDemo {
            return DemoData.queries(page: page, pageSize: pageSize, range: range, filter: filter, domain: domain, client: client, instanceId: instanceId)
        }
        var path = "/api/queries?page=\(page)&page_size=\(pageSize)&\(range.queryString())"
        if let q = filter.queryParam { path += "&\(q)" }
        if let d = Self.queryValue(domain) { path += "&domain=\(d)" }
        if let c = Self.queryValue(client) { path += "&client=\(c)" }
        if let inst = Self.queryValue(instanceId) { path += "&instance_id=\(inst)" }
        return try await get(path)
    }

    /// Aggregated per-client stats, grouped server-side. Used by the Unique Clients drill-down.
    func clients(range: TimeRange, instanceId: String? = nil) async throws -> [ClientSummary] {
        if site.isDemo { return DemoData.clients(range: range, instanceId: instanceId) }
        var path = "/api/queries/clients?\(range.queryString())"
        if let inst = Self.queryValue(instanceId) { path += "&instance_id=\(inst)" }
        return try await get(path)
    }

    /// Active Pi-hole instances (devices) on the server. Backs the Device
    /// filter on the Query Log — same source as the web UI's dropdown.
    /// The response is a superset of `InstanceSummary`, so it decodes as-is.
    func instances() async throws -> [InstanceSummary] {
        if site.isDemo { return DemoData.instances() }
        return try await get("/api/instances")
    }

    // MARK: - Domain lists (read-only)

    /// Allow/deny-list membership for a domain, read live from the site's
    /// master Pi-hole. Read-only — works with a read-only API key.
    func domainStatus(_ domain: String) async throws -> DomainListStatus {
        if site.isDemo { return DemoData.domainStatus(domain) }
        guard let segment = Self.domainPathSegment(domain) else { throw URLError(.badURL) }
        return try await get("/api/domains/status/\(segment)")
    }

    /// Which adlist / deny entries block a domain (MyPi server 2.6.0+; older
    /// servers answer 404 and callers treat that as "not available").
    func domainBlocklists(_ domain: String, range: TimeRange) async throws -> DomainBlocklists {
        if site.isDemo { return DemoData.domainBlocklists(domain) }
        guard let segment = Self.domainPathSegment(domain) else { throw URLError(.badURL) }
        return try await get("/api/domains/blocklists/\(segment)?\(range.queryString())")
    }

    // MARK: - URL building

    /// Characters allowed unescaped in a query-string *value*. Stricter than
    /// `.urlQueryAllowed`, which leaves `&`, `=`, `+` and `#` alone — a value
    /// containing them would otherwise add or truncate parameters.
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    /// Trimmed, percent-encoded query value; nil when empty.
    static func queryValue(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
    }

    /// A domain as a single URL path segment, or nil when it isn't one the
    /// server would accept. Domains in the query log come from whatever a
    /// device on the network chose to look up, so they are untrusted input:
    /// only the server's own allowed alphabet (letters, digits, `.`, `_`,
    /// `-`, `*`) is let through, and dot-only names are rejected so a name
    /// like `..` can't re-target the request to a different endpoint.
    static func domainPathSegment(_ raw: String) -> String? {
        let domain = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !domain.isEmpty, domain.count <= 253 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._*-")
        guard domain.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        guard domain.contains(where: { $0 != "." }) else { return nil }
        return domain.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
    }

    /// Global sync state — the timestamp of the last query-log sync run,
    /// plus per-instance success/failure. The sync schedule runs hourly by
    /// default (separate from the stats poll which is much more frequent).
    func syncStatus() async throws -> SyncStatus {
        if site.isDemo { return DemoData.syncStatus() }
        return try await get("/api/sync/status")
    }

    // MARK: - Generic request

    /// Endpoints that are server-global rather than site-scoped. These
    /// keep their original path even when `site.mypiSiteSlug` is set —
    /// `/api/health` returns the server version (no site context) and
    /// `/api/sites` returns the discovery list (rewriting it would
    /// produce nonsense like `/api/sites/cabin/sites`).
    private static let serverGlobalPathPrefixes: [String] = [
        "/api/health",
        "/api/sites",
    ]

    /// Apply multi-site routing to an `/api/...` path. When
    /// `site.mypiSiteSlug` is nil — including for demo sites and for
    /// legacy single-site servers — this returns the path unchanged, so
    /// the server's legacy alias resolves to Main exactly like before.
    /// `internal` rather than `private` so unit tests can exercise the
    /// path-rewriting rules directly (this is server-routing logic, not
    /// just an implementation detail).
    func resolvedPath(_ path: String) -> String {
        guard let slug = site.mypiSiteSlug, !slug.isEmpty else { return path }
        if Self.serverGlobalPathPrefixes.contains(where: { path.hasPrefix($0) }) {
            return path
        }
        guard path.hasPrefix("/api/") else { return path }
        // Slugs are server-assigned `[a-z0-9-]`; encoding anything else keeps
        // an unexpected value inside its own path segment.
        let segment = slug.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) ?? slug
        return "/api/sites/\(segment)/" + String(path.dropFirst("/api/".count))
    }

    func get<T: Decodable>(_ path: String, authenticated: Bool = true) async throws -> T {
        let routed = resolvedPath(path)
        guard let url = URL(string: routed, relativeTo: site.baseURL)?.absoluteURL else {
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

/// Carries the fingerprint from URLSession's delegate queue back to the caller.
private final class FingerprintBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var value: String? { lock.withLock { stored } }
    func set(_ fingerprint: String) { lock.withLock { stored = fingerprint } }
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
