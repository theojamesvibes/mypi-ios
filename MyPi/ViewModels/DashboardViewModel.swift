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

    var site: Site { client.site }

    // Stale after 2 missed poll cycles (populated from /api/health on first load).
    private var staleThresholdSeconds: Double = 120

    /// Effective seconds until the next poll attempt, including failure backoff.
    /// Surfaced so the "site unreachable — retrying every Xs" banner can show
    /// the user what the current cadence is without having to guess.
    var currentPollIntervalSeconds: Int {
        let base = staleThresholdSeconds / 2
        let backoff = min(pow(2.0, Double(consecutiveFailures)), 16)
        return Int((base * max(1, backoff)).rounded())
    }

    /// Consecutive failed `fetchAll()` attempts. Drives poll-interval backoff
    /// and the confidence gate for declaring the site unreachable — a single
    /// transient failure (brief network blip, DNS hiccup) shouldn't flip the
    /// banner; we require at least two in a row to be sure.
    private(set) var consecutiveFailures: Int = 0

    /// Minimum failure streak before the UI should treat the site as
    /// genuinely down. Kept at 2 so one-off failures don't flash the
    /// unreachable banner over known-good cached data.
    static let unreachableFailureThreshold = 2

    /// True while we're in the quiet window right after `start()` — used to
    /// suppress the unreachable banner for a few seconds on site switch /
    /// tab resume so a stale failure streak from the previous session
    /// doesn't flash before the fresh fetch has a chance to clear it.
    /// `@Observable` picks up the flip so views re-render when the grace
    /// ends.
    private(set) var isWithinStartupGrace: Bool = false
    private var graceTask: Task<Void, Never>?
    static let startupGraceSeconds: Double = 5

    var isSiteUnreachable: Bool {
        !isWithinStartupGrace && consecutiveFailures >= Self.unreachableFailureThreshold
    }

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
        graceTask?.cancel()
    }

    // MARK: - Public

    func start() {
        beginStartupGrace()
        Task { [weak self] in await self?.loadCachedThenFetch() }
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        graceTask?.cancel()
        graceTask = nil
        isWithinStartupGrace = false
    }

    /// Open a short quiet window during which `isSiteUnreachable` reports
    /// false regardless of the failure streak. Fired from `start()` so every
    /// site switch / tab resume gets the grace, but only once per resume —
    /// not per fetch.
    private func beginStartupGrace() {
        graceTask?.cancel()
        isWithinStartupGrace = true
        graceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.startupGraceSeconds))
            guard !Task.isCancelled else { return }
            self?.isWithinStartupGrace = false
        }
    }

    /// Force a fetch regardless of the recent-fetch debounce. Used by
    /// pull-to-refresh and the error-view retry button — when the user
    /// explicitly asks for fresh data we don't skip it.
    func refresh() async {
        await fetchAll(force: true)
    }

    // MARK: - Private

    /// Hydrate summary + history + top + syncStatus from disk on first mount
    /// so a site visit always has *something* to show — even if the server
    /// is unreachable right now. Only fills fields that are still nil so a
    /// later `start()` after an in-memory fetch doesn't clobber fresh data
    /// with whatever was on disk.
    private func loadCachedThenFetch() async {
        if summary == nil,
           let cached = DiskCache.shared.read(key: cacheKeyPrefix + "-summary", as: AggregatedSummary.self) {
            summary = cached.data
            lastUpdated = cached.fetchedAt
            isStale = Date().timeIntervalSince(cached.fetchedAt) > staleThresholdSeconds
            loadState = .loaded
        }
        if history == nil,
           let cached = DiskCache.shared.read(key: cacheKeyPrefix + "-history", as: HistoryResponse.self) {
            history = cached.data
        }
        if top == nil,
           let cached = DiskCache.shared.read(key: cacheKeyPrefix + "-top", as: TopStatsResponse.self) {
            top = cached.data
        }
        if syncStatus == nil,
           let cached = DiskCache.shared.read(key: cacheKeyPrefix + "-sync", as: SyncStatus.self) {
            syncStatus = cached.data
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
            // Re-fetch /api/health every cycle so Settings reflects the live
            // server version if the server is upgraded under us.
            if let health = try? await client.health() {
                staleThresholdSeconds = Double(health.statsPollInterval) * 2
                serverVersion = health.version
                if let appState, let site = appState.activeSite, site.id == client.site.id {
                    appState.connectionStates[site.id] = .connected(serverVersion: health.version)
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
            if let sync = syncStatus {
                DiskCache.shared.write(sync, key: cacheKeyPrefix + "-sync")
            }
        } catch {
            consecutiveFailures += 1
            if summary != nil {
                // `isStale` lights up the red banner. It should reflect data
                // actually being past the poll window, not just "the latest
                // fetch happened to fail" — a failed refresh a few seconds
                // after a fresh load shouldn't turn the UI red.
                if let last = lastUpdated {
                    isStale = Date().timeIntervalSince(last) > staleThresholdSeconds
                }
                loadState = .loaded
            } else {
                loadState = .failed(error.localizedDescription)
            }
            // Only flip the site's connection state to unreachable after we
            // cross the confidence threshold. Previously a single failure
            // immediately re-probed (two more requests) and overwrote the
            // connected state, so pull-to-refresh during a brief blip
            // painted the unreachable banner until the next successful
            // poll. Categorize the caught error directly — no extra
            // round-trip against a possibly-down server.
            if consecutiveFailures >= Self.unreachableFailureThreshold,
               let appState,
               let site = appState.activeSite,
               site.id == client.site.id {
                appState.connectionStates[site.id] = Self.categorize(error)
            }
        }
    }

    /// Map a caught fetch error to the equivalent `SiteConnectionState`,
    /// mirroring the classification `AppState.probe(site:)` does but without
    /// the extra requests. Kept private + `static` so there's one source of
    /// truth for error → state mapping inside the VM's fetch path.
    private static func categorize(_ error: Error) -> SiteConnectionState {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .serverCertificateUntrusted,
                 .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .clientCertificateRejected:
                return .tlsError(urlErr.localizedDescription)
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .timedOut:
                return .offline
            default:
                return .error(urlErr.localizedDescription)
            }
        }
        if let apiErr = error as? APIError {
            let d = apiErr.detail
            if d.localizedCaseInsensitiveContains("auth") ||
               d.localizedCaseInsensitiveContains("key") ||
               d.localizedCaseInsensitiveContains("invalid") {
                return .unauthorized
            }
            return .error(d)
        }
        return .error(error.localizedDescription)
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
