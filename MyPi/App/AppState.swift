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
            let loaded = try SiteStore.shared.load()
            // Demo sites are session-scoped: wipe on every cold launch so
            // "close the app to exit demo mode" is the user's way out. We
            // only reach this branch when the app process is fresh — if
            // the user just backgrounds and returns, `AppState` is already
            // alive and `init` doesn't run again, so demo mode persists
            // across background/foreground cycles as expected.
            for demo in loaded where demo.isDemo {
                SiteStore.shared.delete(id: demo.id)
            }
            sites = loaded.filter { !$0.isDemo }
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
        // Best-effort migration for users who landed in the broken state
        // before this fix shipped: any non-demo iOS Site with no backend
        // slug is checked against /api/sites; if the server is multi-site
        // we adopt Main's slug so subsequent fetches scope to Main only
        // instead of hitting the aggregate-across-sites legacy alias.
        Task { [weak self] in
            await self?.migrateLegacyNilSlugs()
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
        // Demo sites never hit the network, so skip the connectivity guard —
        // otherwise a device going offline would park a demo site in
        // `.offline` permanently even though its "server" is always local.
        guard site.isDemo || NetworkMonitor.shared.isConnected else {
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

    /// One-shot migration: any non-demo `Site` with `mypiSiteSlug == nil`
    /// is probed against `/api/sites`. If the server is multi-site (≥ 2
    /// active sites returned), the iOS Site is updated in-place to use
    /// Main's slug, so its subsequent requests scope through
    /// `/api/sites/{main-slug}/...` — which the server scopes correctly —
    /// rather than the legacy `/api/...` alias which the server happens to
    /// have implemented as cross-site aggregation.
    ///
    /// Single-site / legacy / unreachable servers are left alone: the
    /// legacy alias is correct for them and the migration is harmless.
    /// If the network isn't up yet, we wait briefly for `NetworkMonitor`
    /// (which defaults to false post-0.1.4) to flip; if that times out we
    /// just return and the migration retries on the next launch.
    @MainActor
    private func migrateLegacyNilSlugs() async {
        // Wait up to ~2 s for the path monitor's first callback. It
        // typically settles in under 100 ms, but fresh installs can have
        // a longer delay before the first `pathUpdateHandler` fires.
        for _ in 0..<10 where !NetworkMonitor.shared.isConnected {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard NetworkMonitor.shared.isConnected else { return }

        // Snapshot candidates — `updateSite` mutates `sites`, so we work
        // off a copy taken before any in-loop changes.
        let candidates = sites.filter { !$0.isDemo && ($0.mypiSiteSlug?.isEmpty ?? true) }
        guard !candidates.isEmpty else { return }

        for candidate in candidates {
            let mypiSites: [MyPiSite]
            do {
                mypiSites = try await client(for: candidate).mypiSites()
            } catch {
                continue  // server is single-site / legacy / unreachable
            }
            guard mypiSites.count >= 2,
                  let main = mypiSites.first(where: { $0.isMain })
            else {
                continue  // truly single-site server — nothing to fix
            }
            // Look up the latest version of this site (in case something
            // mutated it between the snapshot and now), apply the slug,
            // and let `updateSite` invalidate the per-site client + VMs
            // so the next dashboard fetch uses the corrected route.
            guard let current = sites.first(where: { $0.id == candidate.id }) else { continue }
            var updated = current
            updated.mypiSiteSlug = main.slug
            updated.mypiSiteName = main.name
            updateSite(updated)
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
