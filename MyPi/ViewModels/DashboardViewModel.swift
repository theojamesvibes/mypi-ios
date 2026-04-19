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
    var serverVersion: String?

    var selectedRange: TimeRange = .today {
        didSet { Task { await refresh() } }
    }

    // MARK: - Private

    private let client: APIClient
    private weak var appState: AppState?
    private let monitor = NetworkMonitor.shared
    private var pollTask: Task<Void, Never>?

    // Stale after 2 missed poll cycles (populated from /api/health on first load).
    private var staleThresholdSeconds: Double = 120

    private var cacheKeyPrefix: String {
        "dashboard-\(client.site.id.uuidString)"
    }

    init(client: APIClient, appState: AppState? = nil) {
        self.client = client
        self.appState = appState
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
            // Discover poll intervals and capture server version on first fetch.
            if serverVersion == nil {
                if let health = try? await client.health() {
                    staleThresholdSeconds = Double(health.statsPollInterval) * 2
                    serverVersion = health.version
                    if let appState, let site = appState.activeSite, site.id == client.site.id {
                        appState.connectionStates[site.id] = .connected(serverVersion: health.version)
                    }
                }
            }

            async let summaryTask = client.summary(range: selectedRange)
            async let historyTask = client.history(range: selectedRange)
            async let topTask = client.top(range: selectedRange)

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
            await appState?.probe(site: client.site)
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
}
