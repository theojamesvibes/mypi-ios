import Foundation
import Observation

@Observable
final class DashboardViewModel {
    // MARK: - State

    enum LoadState {
        case idle, loading, loaded, failed(String)
    }

    var loadState: LoadState = .idle
    var summary: AggregatedSummary?
    var history: HistoryResponse?
    var top: TopStatsResponse?
    var lastUpdated: Date?
    var isStale: Bool = false

    var selectedHours: Int = 24 {
        didSet { Task { await refresh() } }
    }

    // MARK: - Private

    private let client: APIClient
    private let monitor = NetworkMonitor.shared
    private var pollTask: Task<Void, Never>?

    // Stale after 2 missed poll cycles (populated from /api/health on first load).
    private var staleThresholdSeconds: Double = 120

    private var cacheKeyPrefix: String {
        "dashboard-\(client.site.id.uuidString)"
    }

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Public

    func start() {
        Task { await loadCachedThenFetch() }
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        await fetchAll()
    }

    // MARK: - Private

    private func loadCachedThenFetch() async {
        // Show cached data instantly so the UI is not blank.
        if let cached = DiskCache.shared.read(key: cacheKeyPrefix + "-summary", as: AggregatedSummary.self) {
            summary = cached.data
            lastUpdated = cached.fetchedAt
            isStale = Date().timeIntervalSince(cached.fetchedAt) > staleThresholdSeconds
            loadState = .loaded
        }
        await fetchAll()
    }

    private func fetchAll() async {
        guard monitor.isConnected else { return }
        loadState = .loading
        do {
            // Discover poll intervals on first fetch.
            if staleThresholdSeconds == 120 {
                if let health = try? await client.health() {
                    staleThresholdSeconds = Double(health.statsPollInterval) * 2
                }
            }

            async let summaryTask = client.summary(hours: selectedHours)
            async let historyTask = client.history(hours: selectedHours, bucketMinutes: bucketMinutes(for: selectedHours))
            async let topTask = client.top(hours: selectedHours)

            let (s, h, t) = try await (summaryTask, historyTask, topTask)
            summary = s
            history = h
            top = t
            lastUpdated = Date()
            isStale = false
            loadState = .loaded

            DiskCache.shared.write(s, key: cacheKeyPrefix + "-summary")
            DiskCache.shared.write(h, key: cacheKeyPrefix + "-history")
            DiskCache.shared.write(t, key: cacheKeyPrefix + "-top")
        } catch {
            // Mark stale if we have old data, otherwise show error.
            if summary != nil {
                isStale = true
                loadState = .loaded
            } else {
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(staleThresholdSeconds / 2))
                if !Task.isCancelled {
                    await fetchAll()
                }
            }
        }
    }

    private func bucketMinutes(for hours: Int) -> Int {
        switch hours {
        case 1: return 5
        case 2...6: return 10
        case 7...24: return 30
        case 25...168: return 60
        default: return 120
        }
    }
}
