import SwiftUI

struct AppSettingsView: View {
    @Environment(AppState.self) private var appState
    /// Probe fires once per active-site change rather than on every tab
    /// re-appear. Re-probing on every swipe-in caused a `.probing` →
    /// `.connected` state flip mid-transition, which re-rendered the Form
    /// while the tab was still sliding and looked like an abrupt flash.
    @State private var lastProbedSiteID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                if let site = appState.activeSite, site.isDemo {
                    Section {
                        DemoModeBanner()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Connection") {
                    if let site = appState.activeSite {
                        LabeledContent("Site URL") {
                            Text(site.baseURL.absoluteString)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    statusRow
                    serverVersionRow
                    if let site = appState.activeSite {
                        tlsRow(for: site)
                    }
                }

                Section("About") {
                    LabeledContent("App Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SiteSwitcherMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SiteListView()
                    } label: {
                        Text("Manage Sites")
                    }
                }
            }
            .task {
                guard let site = appState.activeSite,
                      lastProbedSiteID != site.id else { return }
                lastProbedSiteID = site.id
                await appState.probe(site: site)
            }
            .refreshable {
                // Pull-to-refresh still forces a fresh probe — that's the
                // explicit-user-wants-fresh-data path.
                if let site = appState.activeSite {
                    await appState.probe(site: site)
                }
            }
        }
    }

    @ViewBuilder
    private func tlsRow(for site: Site) -> some View {
        let tls = appState.client(for: site).lastTLSVersion
        LabeledContent("TLS") {
            VStack(alignment: .trailing, spacing: 2) {
                if site.allowSelfSigned {
                    Text(tls ?? "—")
                        .foregroundStyle(.yellow)
                    Text(site.pinnedCertFingerprint != nil
                         ? "Self-signed (pinned)"
                         : "Self-signed")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                } else if let tls {
                    Text(tls).foregroundStyle(.green)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        let state = appState.activeSite.flatMap { appState.connectionStates[$0.id] } ?? .unknown
        LabeledContent("Status") {
            HStack(spacing: 6) {
                Circle().fill(state.color).frame(width: 8, height: 8)
                Text(state.label).foregroundStyle(state.color)
            }
        }
    }

    @ViewBuilder
    private var serverVersionRow: some View {
        let version = appState.dashboardVM?.serverVersion
            ?? activeSiteConnectedVersion
        LabeledContent("Server Version", value: version ?? "—")
    }

    private var activeSiteConnectedVersion: String? {
        guard let site = appState.activeSite,
              case .connected(let v) = appState.connectionStates[site.id] ?? .unknown
        else { return nil }
        return v
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
