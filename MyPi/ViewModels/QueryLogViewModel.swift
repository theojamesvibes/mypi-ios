import Foundation
import Observation

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

    var filter: QueryFilter = .all {
        didSet { Task { await reset() } }
    }
    var selectedRange: TimeRange = .today {
        didSet { Task { await reset() } }
    }

    /// Pi-hole devices on the server, for the Device filter chip (mirrors the
    /// web Query Log's instance dropdown). Empty until `loadInitial` fetches
    /// them; the chip stays hidden with fewer than two devices.
    var instances: [InstanceSummary] = []

    /// Server-side `instance_id` filter; nil means all devices.
    var selectedInstanceId: String? {
        didSet { Task { await reset() } }
    }

    var selectedInstanceName: String? {
        guard let id = selectedInstanceId else { return nil }
        return instances.first(where: { $0.id == id })?.name
    }

    var isClientsMode: Bool { filter.isClientsMode }

    var site: Site { client.site }

    /// Local search over every user-visible field so "Search" in the nav bar
    /// covers domain, client IP / name, status, and the Pi-hole instance
    /// name — not just domain (which was the old server-side filter).
    var filteredQueries: [QueryEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return queries }
        return queries.filter { entry in
            entry.domain.localizedCaseInsensitiveContains(q) ||
            entry.clientIp.localizedCaseInsensitiveContains(q) ||
            (entry.clientName ?? "").localizedCaseInsensitiveContains(q) ||
            entry.status.localizedCaseInsensitiveContains(q) ||
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

    private var cacheKeyPrefix: String {
        "querylog-\(client.site.id.uuidString)"
    }

    /// Cache-key fragment for the device filter. Empty when no device is
    /// selected so pre-existing (unfiltered) cache entries stay valid.
    private var instanceKeySuffix: String {
        selectedInstanceId.map { "-inst-\($0)" } ?? ""
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
        if isClientsMode {
            if clients.isEmpty,
               let cached = DiskCache.shared.read(
                   key: cacheKeyPrefix + "-clients-\(selectedRange.id)" + instanceKeySuffix,
                   as: [ClientSummary].self
               ) {
                clients = cached.data
                lastUpdated = cached.fetchedAt
            }
        } else {
            if queries.isEmpty,
               let cached = DiskCache.shared.read(
                   key: cacheKeyPrefix + "-queries-\(filter.rawValue)-\(selectedRange.id)" + instanceKeySuffix,
                   as: [QueryEntry].self
               ) {
                queries = cached.data
                lastUpdated = cached.fetchedAt
            }
        }
    }

    func loadNextPage() async {
        guard !isLoading, !isClientsMode, currentPage < totalPages else { return }
        currentPage += 1
        await fetchPage(currentPage, appending: true)
    }

    func refresh() async {
        await reset()
    }

    // MARK: - Private

    /// Fetch page 1 (or the clients aggregate) without eagerly clearing the
    /// existing list — keeps the List mounted during the async fetch so the
    /// pull-to-refresh gesture stays attached and the UI doesn't flash a
    /// loading/error state when refreshing a populated list. fetchPage
    /// replaces contents on success.
    private func reset() async {
        currentPage = 1
        if isClientsMode {
            await fetchClients()
        } else {
            await fetchPage(1, appending: false)
        }
    }

    /// Server-side `domain=` search was removed so the single Search box in
    /// the nav bar covers every field (domain, client IP/name, status,
    /// instance) locally. Pagination + filter/range still go to the server.
    private func fetchPage(_ page: Int, appending: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await client.queries(
                page: page,
                pageSize: pageSize,
                range: selectedRange,
                filter: filter,
                domain: nil,
                instanceId: selectedInstanceId
            )
            if appending {
                queries.append(contentsOf: result.items)
            } else {
                queries = result.items
                clients = []  // leave clients-mode state clean
            }
            totalPages = result.pages
            hasMore = page < result.pages
            lastUpdated = Date()
            if page == 1 {
                DiskCache.shared.write(
                    queries,
                    key: cacheKeyPrefix + "-queries-\(filter.rawValue)-\(selectedRange.id)" + instanceKeySuffix
                )
            }
        } catch {
            // Keep existing rows visible if we already have data — a failed
            // refresh on an unreachable site should fall back to cache, not
            // replace the list with an error screen.
            if queries.isEmpty {
                errorMessage = ErrorMessage.userFacing(error)
            }
        }
        isLoading = false
    }

    private func fetchClients() async {
        isLoading = true
        errorMessage = nil
        do {
            clients = try await client.clients(range: selectedRange, instanceId: selectedInstanceId)
            queries = []
            hasMore = false
            lastUpdated = Date()
            DiskCache.shared.write(
                clients,
                key: cacheKeyPrefix + "-clients-\(selectedRange.id)" + instanceKeySuffix
            )
        } catch {
            if clients.isEmpty {
                errorMessage = ErrorMessage.userFacing(error)
            }
        }
        isLoading = false
    }
}
