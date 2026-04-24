import Foundation
import Observation

/// Top-level application state shared across the view hierarchy via the environment.
@Observable
final class AppState {
    // MARK: - Sites

    /// All configured sites, ordered as stored.
    private(set) var sites: [Site] = []

    /// The index of the currently active site (nil = none configured).
    var activeSiteIndex: Int? {
        didSet { activeSiteChanged() }
    }

    var activeSite: Site? {
        guard let idx = activeSiteIndex, sites.indices.contains(idx) else { return nil }
        return sites[idx]
    }

    // MARK: - Onboarding

    var showSetupSheet: Bool = false

    // MARK: - Per-site clients, view models, and connection state

    private var clientsByID: [UUID: APIClient] = [:]
    private var dashboardVMsByID: [UUID: DashboardViewModel] = [:]
    private var queryLogVMsByID: [UUID: QueryLogViewModel] = [:]

    var dashboardVM: DashboardViewModel? {
        guard let site = activeSite else { return nil }
        return dashboardVMsByID[site.id]
    }

    var queryLogVM: QueryLogViewModel? {
        guard let site = activeSite else { return nil }
        return queryLogVMsByID[site.id]
    }

    /// Observed connection state per site (used by Settings and the Sites list).
    var connectionStates: [UUID: SiteConnectionState] = [:]

    /// Non-nil when `SiteStore.load()` threw on launch because `sites.json`
    /// was on disk but couldn't be decoded. We park here so ContentView can
    /// render a recoverable error screen instead of silently dropping the
    /// user into onboarding — which would feel like "all my sites vanished"
    /// and, worse, invite them to overwrite the salvageable file by adding
    /// a new site.
    private(set) var loadError: String?

    // MARK: - Init

    init() {
        do {
            sites = try SiteStore.shared.load()
            if sites.isEmpty {
                showSetupSheet = true
            } else {
                activeSiteIndex = 0
            }
        } catch {
            // Don't touch `sites.json` — leave it intact for manual recovery.
            // Leave `showSetupSheet` false so the error screen has the UI.
            loadError = error.localizedDescription
        }
    }

    // MARK: - Public

    func addSite(_ site: Site) {
        SiteStore.shared.save(site)
        sites = (try? SiteStore.shared.load()) ?? []
        if activeSiteIndex == nil {
            activeSiteIndex = 0
        }
    }

    func updateSite(_ site: Site) {
        SiteStore.shared.save(site)
        sites = (try? SiteStore.shared.load()) ?? []
        // Invalidate client + VMs so they pick up new settings.
        clientsByID[site.id] = nil
        dashboardVMsByID[site.id]?.stop()
        dashboardVMsByID[site.id] = nil
        queryLogVMsByID[site.id] = nil
        connectionStates[site.id] = .unknown
        activeSiteChanged()
    }

    func deleteSite(at offsets: IndexSet) {
        for idx in offsets {
            let site = sites[idx]
            SiteStore.shared.delete(id: site.id)
            clientsByID[site.id] = nil
            dashboardVMsByID[site.id]?.stop()
            dashboardVMsByID[site.id] = nil
            queryLogVMsByID[site.id] = nil
            connectionStates[site.id] = nil
        }
        sites = (try? SiteStore.shared.load()) ?? []
        if sites.isEmpty {
            activeSiteIndex = nil
            showSetupSheet = true
        } else {
            activeSiteIndex = min(activeSiteIndex ?? 0, sites.count - 1)
        }
    }

    func client(for site: Site) -> APIClient {
        if let existing = clientsByID[site.id] { return existing }
        let c = APIClient(site: site)
        clientsByID[site.id] = c
        return c
    }

    /// Refresh the dashboard for the active site (used by background task and pull-to-refresh).
    func refreshActiveSite() async {
        await dashboardVM?.refresh()
    }

    /// Probe a site's connectivity and update `connectionStates[site.id]`.
    /// Runs health (unauthenticated) then summary (authenticated) to distinguish
    /// offline / TLS / unauthorized / connected.
    @MainActor
    func probe(site: Site) async {
        guard NetworkMonitor.shared.isConnected else {
            connectionStates[site.id] = .offline
            return
        }
        connectionStates[site.id] = .probing
        let c = client(for: site)
        let health: HealthResponse
        do {
            health = try await c.health()
        } catch let urlErr as URLError where urlErr.code == .serverCertificateUntrusted ||
                                              urlErr.code == .serverCertificateHasBadDate ||
                                              urlErr.code == .serverCertificateHasUnknownRoot ||
                                              urlErr.code == .serverCertificateNotYetValid ||
                                              urlErr.code == .clientCertificateRejected {
            connectionStates[site.id] = .tlsError(urlErr.localizedDescription)
            return
        } catch let urlErr as URLError where urlErr.code == .notConnectedToInternet ||
                                              urlErr.code == .networkConnectionLost {
            connectionStates[site.id] = .offline
            return
        } catch {
            connectionStates[site.id] = .error(error.localizedDescription)
            return
        }
        do {
            _ = try await c.summary(range: .hour1)
            connectionStates[site.id] = .connected(serverVersion: health.version)
        } catch let apiErr as APIError {
            // 401 / missing key / wrong key
            if apiErr.detail.localizedCaseInsensitiveContains("auth") ||
               apiErr.detail.localizedCaseInsensitiveContains("key") ||
               apiErr.detail.localizedCaseInsensitiveContains("invalid") {
                connectionStates[site.id] = .unauthorized
            } else {
                connectionStates[site.id] = .error(apiErr.detail)
            }
        } catch {
            connectionStates[site.id] = .error(error.localizedDescription)
        }
    }

    /// Probe every configured site in parallel.
    func probeAll() async {
        await withTaskGroup(of: Void.self) { group in
            for site in sites {
                group.addTask { [weak self] in
                    await self?.probe(site: site)
                }
            }
        }
    }

    // MARK: - Private

    /// Re-uses previously-built view models per site so switching sites
    /// doesn't throw away in-memory dashboard/query-log state. Only the first
    /// time we see a site do we instantiate fresh VMs (they'll rehydrate from
    /// disk cache if data exists).
    private func activeSiteChanged() {
        guard let site = activeSite else { return }
        let c = client(for: site)
        if dashboardVMsByID[site.id] == nil {
            dashboardVMsByID[site.id] = DashboardViewModel(client: c, appState: self)
        }
        if queryLogVMsByID[site.id] == nil {
            queryLogVMsByID[site.id] = QueryLogViewModel(client: c)
        }
        Task { await probe(site: site) }
    }
}
