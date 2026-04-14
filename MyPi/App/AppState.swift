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

    // MARK: - Per-site clients & view models

    private var clientsByID: [UUID: APIClient] = [:]
    private(set) var dashboardVM: DashboardViewModel?
    private(set) var queryLogVM: QueryLogViewModel?

    // MARK: - Init

    init() {
        sites = SiteStore.shared.load()
        if sites.isEmpty {
            showSetupSheet = true
        } else {
            activeSiteIndex = 0
        }
    }

    // MARK: - Public

    func addSite(_ site: Site) {
        SiteStore.shared.save(site)
        sites = SiteStore.shared.load()
        if activeSiteIndex == nil {
            activeSiteIndex = 0
        }
    }

    func updateSite(_ site: Site) {
        SiteStore.shared.save(site)
        sites = SiteStore.shared.load()
        // Invalidate client so it picks up new settings.
        clientsByID[site.id] = nil
        activeSiteChanged()
    }

    func deleteSite(at offsets: IndexSet) {
        for idx in offsets {
            let site = sites[idx]
            SiteStore.shared.delete(id: site.id)
            clientsByID[site.id] = nil
        }
        sites = SiteStore.shared.load()
        if sites.isEmpty {
            activeSiteIndex = nil
            dashboardVM = nil
            queryLogVM = nil
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

    // MARK: - Private

    private func activeSiteChanged() {
        guard let site = activeSite else {
            dashboardVM = nil
            queryLogVM = nil
            return
        }
        let c = client(for: site)
        dashboardVM = DashboardViewModel(client: c)
        queryLogVM = QueryLogViewModel(client: c)
    }
}
