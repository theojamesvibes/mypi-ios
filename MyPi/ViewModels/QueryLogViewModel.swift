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

    var filter: QueryFilter = .all {
        didSet { Task { await reset() } }
    }
    var selectedRange: TimeRange = .today {
        didSet { Task { await reset() } }
    }

    var isClientsMode: Bool { filter.isClientsMode }

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

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Public

    func loadInitial() async {
        await reset()
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

    private func fetchPage(_ page: Int, appending: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await client.queries(
                page: page,
                pageSize: pageSize,
                range: selectedRange,
                filter: filter,
                domain: searchText
            )
            if appending {
                queries.append(contentsOf: result.items)
            } else {
                queries = result.items
                clients = []  // leave clients-mode state clean
            }
            totalPages = result.pages
            hasMore = page < result.pages
        } catch {
            errorMessage = error.localizedDescription
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
