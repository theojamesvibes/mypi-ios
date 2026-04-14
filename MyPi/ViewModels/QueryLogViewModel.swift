import Foundation
import Observation

@Observable
final class QueryLogViewModel {
    // MARK: - State

    var queries: [QueryEntry] = []
    var isLoading: Bool = false
    var hasMore: Bool = false
    var errorMessage: String?

    var filter: QueryFilter = .all {
        didSet { Task { await reset() } }
    }
    var selectedHours: Int = 24 {
        didSet { Task { await reset() } }
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
        guard !isLoading, currentPage < totalPages else { return }
        currentPage += 1
        await fetchPage(currentPage, appending: true)
    }

    func refresh() async {
        await reset()
    }

    // MARK: - Private

    private func reset() async {
        currentPage = 1
        queries = []
        await fetchPage(1, appending: false)
    }

    private func fetchPage(_ page: Int, appending: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await client.queries(
                page: page,
                pageSize: pageSize,
                hours: selectedHours,
                filter: filter
            )
            if appending {
                queries.append(contentsOf: result.items)
            } else {
                queries = result.items
            }
            totalPages = result.pages
            hasMore = page < result.pages
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
