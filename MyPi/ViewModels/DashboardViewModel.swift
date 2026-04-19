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
    var syncStatus: SyncStatus?
    var lastUpdated: Date?
    var isStale: Bool = false
    var serverVersion: String?

    var selectedRange: TimeRange = .today {
        didSet { Task { [weak self] in await self?.refresh() } }
    }

    // MARK: - Private

    private let client: APIClient
    private weak var appState: AppState?
    private let monitor = NetworkMonitor.shared
    private var pollTask: Task<Void, Never>?

    // Stale after 2 missed poll cycles (populated from /api/health on first load).
    private var staleThresholdSeconds: Double = 120

    /// Consecutive failed `fetchAll()` attempts. Used to back off the poll
    /// interval so a site that's down doesn't produce a steady
    /// 4-requests-per-minute stream of failures.
    private var consecutiveFailures: Int = 0

    /// Skip any `fetchAll` call that lands within this many seconds of the
    /// previous successful one. Prevents scenePhase foreground + poll-tick +
    /// tab-re-`onAppear` from triple-firing against the server.
    private let minFetchInterval: TimeInterval = 5

    private var cacheKeyPrefix: String {
        "dashboard-\(client.site.id.uuidString)"
    }

    init(client: APIClient, appState: AppState? = nil) {
        self.client = client
        self.appState = appState
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Public

    func start() {
        Task { [weak self] in await self?.loadCachedThenFetch() }
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Force a fetch regardless of the recent-fetch debounce. Used by
    /// pull-to-refresh and the error-view retry button — when the user
    /// explicitly asks for fresh data we don't skip it.
    func refresh() async {
        await fetchAll(force: true)
    }

    // MARK: - Private

    private func loadCachedThenFetch() async {
        if let cached = DiskCache.shared.read(key: cacheKeyPrefix + "-summary", as: AggregatedSummary.self) {
            summary = cached.data
            lastUpdated = cached.fetchedAt
            isStale = Date().timeIntervalSince(cached.fetchedAt) > staleThresholdSeconds
            loadState = .loaded
        }
        await fetchAll(force: true)
    }

    /// Fetch summary/history/top (plus sync status) for the active site.
    /// `force == false` debounces against the most recent successful fetch
    /// so scenePhase + poll + onAppear can't triple-trigger within
    /// `minFetchInterval` seconds.
    private func fetchAll(force: Bool = false) async {
        guard monitor.isConnected else { return }
        if !force, let last = lastUpdated,
           Date().timeIntervalSince(last) < minFetchInterval {
            return
        }
        loadState = .loading
        do {
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
            if let sync = try? await client.syncStatus() {
                syncStatus = sync
            }
            lastUpdated = Date()
            isStale = false
            loadState = .loaded
            consecutiveFailures = 0

            DiskCache.shared.write(s, key: cacheKeyPrefix + "-summary")
            DiskCache.shared.write(h, key: cacheKeyPrefix + "-history")
            DiskCache.shared.write(t, key: cacheKeyPrefix + "-top")
        } catch {
            consecutiveFailures += 1
            if summary != nil {
                isStale = true
                loadState = .loaded
            } else {
                loadState = .failed(error.localizedDescription)
            }
            // Only re-probe site health on the first failure of a streak —
            // otherwise a down site multiplies into health+summary+4 polls
            // of requests per cycle.
            if consecutiveFailures == 1 {
                await appState?.probe(site: client.site)
            }
        }
    }

    /// Poll cadence: half the server's stats poll interval on success; doubled
    /// each consecutive failure up to a ceiling. `[weak self]` breaks the
    /// self ↔ task retain cycle so a replaced VM can deallocate.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let base = self.staleThresholdSeconds / 2
                let backoff = min(pow(2.0, Double(self.consecutiveFailures)), 16)
                let interval = base * max(1, backoff)
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                await self.fetchAll()
            }
        }
    }
}
