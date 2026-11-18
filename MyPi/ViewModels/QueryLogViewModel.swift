import Foundation
import Observation

/// State for the Query Log tab. Main-actor isolated: every property here is
/// read by SwiftUI during rendering, so all mutation has to happen on the
/// main thread — the network calls themselves still run off it inside
/// `APIClient`.
@MainActor
@Observable
final class QueryLogViewModel {
    // MARK: - State

    var queries: [QueryEntry] = []
    var clients: [ClientSummary] = []
    var isLoading: Bool = false
    var hasMore: Bool = false
    var errorMessage: String?
    var searchText: String = ""
    var lastUpdated: Date?

    /// Total rows matching the current server-side filters (all pages).
    var totalCount: Int?

    /// Set when fetching a *further* page failed. The rows already loaded
    /// stay on screen and the list footer offers a retry.
    var pageErrorMessage: String?

    var filter: QueryFilter = .all {
        didSet { if filter != oldValue { scheduleReset() } }
    }
    var selectedRange: TimeRange = .today {
        didSet { if selectedRange != oldValue { scheduleReset() } }
    }

    /// Pi-hole devices on the server, for the Device filter chip (mirrors the
    /// web Query Log's instance dropdown). Empty until `loadInitial` fetches
    /// them; the chip stays hidden with fewer than two devices.
    var instances: [InstanceSummary] = []

    /// Server-side `instance_id` filter; nil means all devices.
    var selectedInstanceId: String? {
        didSet { if selectedInstanceId != oldValue { scheduleReset() } }
    }

    /// Server-side `domain=` filter (substring match, like the Domain box on
    /// the web Query Log). Set from the query detail screen; unlike the
    /// search field it reaches every page, not just the rows already loaded.
    var domainFilter: String? {
        didSet { if domainFilter != oldValue { scheduleReset() } }
    }

    /// Server-side `client=` filter (IP or name substring, like the Client
    /// box on the web Query Log).
    var clientFilter: String? {
        didSet { if clientFilter != oldValue { scheduleReset() } }
    }

    var selectedInstanceName: String? {
        guard let id = selectedInstanceId else { return nil }
        return instances.first(where: { $0.id == id })?.name
    }

    var isClientsMode: Bool { filter.isClientsMode }

    var site: Site { client.site }

    /// Local search over every user-visible field so "Search" in the nav bar
    /// covers domain, client IP / name, status, type, and the Pi-hole
    /// instance name. Only searches rows already loaded — the Domain / Client
    /// filters are the server-side equivalents.
    var filteredQueries: [QueryEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return queries }
        return queries.filter { entry in
            entry.domain.localizedCaseInsensitiveContains(q) ||
            entry.clientIp.localizedCaseInsensitiveContains(q) ||
            (entry.clientName ?? "").localizedCaseInsensitiveContains(q) ||
            entry.status.localizedCaseInsensitiveContains(q) ||
            (entry.queryType ?? "").localizedCaseInsensitiveContains(q) ||
            (entry.instanceName ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    /// Clients mode filters locally on name/IP since `/api/queries/clients`
    /// doesn't take a search param.
    var filteredClients: [ClientSummary] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return clients }
        return clients.filter {
            $0.displayName.localizedCaseInsensitiveContains(q) ||
            $0.clientIp.localizedCaseInsensitiveContains(q)
        }
    }

    // MARK: - Private

    private let client: APIClient
    private var currentPage: Int = 1
    private var totalPages: Int = 1
    private let pageSize: Int = 50
    private var hasHydratedFromCache = false

    /// Bumped by every reset. A fetch captures the value when it starts and
    /// drops its response if a newer reset has begun since — otherwise a slow
    /// response for the *previous* filter could land after (and overwrite)
    /// the rows for the current one, and be cached under the wrong key.
    private var generation: Int = 0

    /// The filters a request was issued with, captured before the first
    /// `await` so the response is applied and cached against what was
    /// actually asked for rather than whatever is selected by then.
    private struct Scope: Equatable {
        let filter: QueryFilter
        let range: TimeRange
        let instanceId: String?
        let domain: String?
        let client: String?

        var isClientsMode: Bool { filter.isClientsMode }

        /// Only the plain filter/range/device views are cached to disk. A
        /// domain- or client-narrowed view is an ad-hoc drill-down: caching
        /// it would add a file per value ever tapped.
        var isCacheable: Bool { domain == nil && client == nil }

        func cacheKey(prefix: String) -> String {
            let instance = instanceId.map { "-inst-\($0)" } ?? ""
            if isClientsMode {
                return prefix + "-clients-\(range.id)" + instance
            }
            return prefix + "-queries-\(filter.rawValue)-\(range.id)" + instance
        }
    }

    private var scope: Scope {
        Scope(
            filter: filter,
            range: selectedRange,
            instanceId: selectedInstanceId,
            domain: isClientsMode ? nil : domainFilter,
            client: isClientsMode ? nil : clientFilter
        )
    }

    private var cacheKeyPrefix: String {
        "querylog-\(client.site.id.uuidString)"
    }

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Public

    func loadInitial() async {
        hydrateFromCacheIfNeeded()
        async let deviceList: Void = loadInstances()
        await reset()
        await deviceList
    }

    func loadNextPage() async {
        guard !isLoading, !isClientsMode, currentPage < totalPages else { return }
        await fetchPage(currentPage + 1, appending: true)
    }

    func refresh() async {
        await reset()
    }

    /// Narrow the log to one domain (server-side) and leave Unique Clients
    /// mode if it was active, since that view ignores the domain.
    func showQueries(forDomain domain: String) {
        let trimmed = domain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchText = ""
        if isClientsMode { filter = .all }
        domainFilter = trimmed
    }

    /// Narrow the log to one client (server-side), matching on IP or name.
    func showQueries(forClient client: String) {
        let trimmed = client.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchText = ""
        if isClientsMode { filter = .all }
        clientFilter = trimmed
    }

    // MARK: - Private

    /// Several filters can change in one go (e.g. leaving Unique Clients
    /// *and* setting a domain); coalesce them into a single reset.
    private var resetScheduled = false

    private func scheduleReset() {
        guard !resetScheduled else { return }
        resetScheduled = true
        Task {
            resetScheduled = false
            await reset()
        }
    }

    /// Fetch the device list for the Device chip. Failure is non-fatal —
    /// the chip simply stays hidden (e.g. legacy servers without
    /// `/api/instances`, or a site that's currently unreachable).
    private func loadInstances() async {
        guard instances.isEmpty else { return }
        instances = (try? await client.instances()) ?? []
    }

    /// One-shot disk-cache hydration for the first page (per filter/range).
    /// Shows *something* immediately on a cold site visit even if the server
    /// is unreachable — reset() then races a fresh fetch against it.
    private func hydrateFromCacheIfNeeded() {
        guard !hasHydratedFromCache else { return }
        hasHydratedFromCache = true
        let scope = scope
        guard scope.isCacheable else { return }
        let key = scope.cacheKey(prefix: cacheKeyPrefix)
        if scope.isClientsMode {
            if clients.isEmpty,
               let cached = DiskCache.shared.read(key: key, as: [ClientSummary].self) {
                clients = cached.data
                lastUpdated = cached.fetchedAt
                lastAppliedScope = scope
            }
        } else {
            if queries.isEmpty,
               let cached = DiskCache.shared.read(key: key, as: [QueryEntry].self) {
                queries = cached.data
                lastUpdated = cached.fetchedAt
                lastAppliedScope = scope
            }
        }
    }

    /// A first-page fetch failed. If the rows on screen were fetched with
    /// the same filters, keep them (an unreachable site falls back to what's
    /// already shown). If the filters changed, the old rows no longer match
    /// the chips: swap in the cached page for the new filters when there is
    /// one, otherwise show the error.
    private func handleFirstPageFailure(_ error: Error, scope: Scope) {
        let hasRows = scope.isClientsMode ? !clients.isEmpty : !queries.isEmpty
        if hasRows, scope == lastAppliedScope { return }

        hasMore = false
        totalCount = nil
        if scope.isCacheable {
            let key = scope.cacheKey(prefix: cacheKeyPrefix)
            if scope.isClientsMode,
               let cached = DiskCache.shared.read(key: key, as: [ClientSummary].self) {
                clients = cached.data
                queries = []
                lastUpdated = cached.fetchedAt
                lastAppliedScope = scope
                return
            }
            if !scope.isClientsMode,
               let cached = DiskCache.shared.read(key: key, as: [QueryEntry].self) {
                queries = cached.data
                clients = []
                lastUpdated = cached.fetchedAt
                lastAppliedScope = scope
                return
            }
        }
        queries = []
        clients = []
        lastAppliedScope = nil
        errorMessage = ErrorMessage.userFacing(error)
    }

    /// Fetch page 1 (or the clients aggregate) without eagerly clearing the
    /// existing list — keeps the List mounted during the async fetch so the
    /// pull-to-refresh gesture stays attached and the UI doesn't flash a
    /// loading/error state when refreshing a populated list. fetchPage
    /// replaces contents on success.
    private func reset() async {
        generation += 1
        if isClientsMode {
            await fetchClients()
        } else {
            await fetchPage(1, appending: false)
        }
    }

    /// Pagination + every filter chip go to the server; the Search box is
    /// applied locally over the loaded rows.
    private func fetchPage(_ page: Int, appending: Bool) async {
        let scope = scope
        let requestGeneration = generation
        isLoading = true
        if !appending { errorMessage = nil }
        pageErrorMessage = nil
        do {
            let result = try await client.queries(
                page: page,
                pageSize: pageSize,
                range: scope.range,
                filter: scope.filter,
                domain: scope.domain,
                client: scope.client,
                instanceId: scope.instanceId
            )
            // A newer reset started while this was in flight — its own fetch
            // owns the list (and `isLoading`) now.
            guard requestGeneration == generation else { return }
            if appending {
                // The log is newest-first and still growing, so by the time
                // page N+1 is requested rows have shifted down and the page
                // can repeat entries from page N. Duplicate ids would break
                // the list's row identity, so keep the first occurrence.
                var seen = Set(queries.map(\.id))
                queries.append(contentsOf: result.items.filter { seen.insert($0.id).inserted })
            } else {
                queries = result.items
                clients = []  // leave clients-mode state clean
            }
            currentPage = page
            totalPages = result.pages
            totalCount = result.total
            // An empty page means the server has nothing further, whatever
            // the page arithmetic says — stop rather than refetch forever.
            hasMore = page < result.pages && !result.items.isEmpty
            lastUpdated = Date()
            if !appending { lastAppliedScope = scope }
            if page == 1, scope.isCacheable {
                DiskCache.shared.write(queries, key: scope.cacheKey(prefix: cacheKeyPrefix))
            }
        } catch {
            guard requestGeneration == generation else { return }
            if appending {
                // `currentPage` is only advanced on success, so retrying
                // asks for the same page again instead of skipping it.
                pageErrorMessage = ErrorMessage.userFacing(error)
            } else {
                handleFirstPageFailure(error, scope: scope)
            }
        }
        isLoading = false
    }

    /// Filters the rows currently on screen were fetched with.
    private var lastAppliedScope: Scope?

    private func fetchClients() async {
        let scope = scope
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        pageErrorMessage = nil
        do {
            let result = try await client.clients(range: scope.range, instanceId: scope.instanceId)
            guard requestGeneration == generation else { return }
            clients = result
            queries = []
            hasMore = false
            totalCount = nil
            lastUpdated = Date()
            lastAppliedScope = scope
            DiskCache.shared.write(clients, key: scope.cacheKey(prefix: cacheKeyPrefix))
        } catch {
            guard requestGeneration == generation else { return }
            handleFirstPageFailure(error, scope: scope)
        }
        isLoading = false
    }
}
