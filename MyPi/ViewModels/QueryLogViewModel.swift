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

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Public

    func loadInitial() async {
        hydrateFromCacheIfNeeded()
        await reset()
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
                   key: cacheKeyPrefix + "-clients-\(selectedRange.id)",
                   as: [ClientSummary].self
               ) {
                clients = cached.data
                lastUpdated = cached.fetchedAt
            }
        } else {
            if queries.isEmpty,
               let cached = DiskCache.shared.read(
                   key: cacheKeyPrefix + "-queries-\(filter.rawValue)-\(selectedRange.id)",
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
                domain: nil
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
                    key: cacheKeyPrefix + "-queries-\(filter.rawValue)-\(selectedRange.id)"
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
            clients = try await client.clients(range: selectedRange)
            queries = []
            hasMore = false
            lastUpdated = Date()
            DiskCache.shared.write(
                clients,
                key: cacheKeyPrefix + "-clients-\(selectedRange.id)"
            )
        } catch {
            if clients.isEmpty {
                errorMessage = ErrorMessage.userFacing(error)
            }
        }
        isLoading = false
    }
}
