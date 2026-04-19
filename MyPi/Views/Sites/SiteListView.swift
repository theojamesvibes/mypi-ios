import SwiftUI

/// Manage Sites — reached from the Settings toolbar. Shows the configured
/// sites, each tappable to open SiteFormView for edit/delete, plus a `+`
/// toolbar item to add a new one. Intentionally minimal; switching the
/// active site is done from the SiteSwitcherMenu at the top of every screen.
struct SiteListView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false

    var body: some View {
        List {
            ForEach(Array(appState.sites.enumerated()), id: \.element.id) { idx, site in
                NavigationLink {
                    SiteFormView(site: site)
                } label: {
                    SiteRow(
                        site: site,
                        isActive: appState.activeSiteIndex == idx,
                        connection: appState.connectionStates[site.id] ?? .unknown
                    )
                }
            }
        }
        .navigationTitle("Manage Sites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Site")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            SetupSheet()
        }
        .task { await appState.probeAll() }
        .refreshable { await appState.probeAll() }
    }
}

private struct SiteRow: View {
    let site: Site
    let isActive: Bool
    let connection: SiteConnectionState

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(connection.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(site.name).font(.headline)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    }
                }
                Text(site.baseURL.host() ?? site.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(connection.label)
                    .font(.caption2)
                    .foregroundStyle(connection.color)
            }
            Spacer()
        }
    }
}
