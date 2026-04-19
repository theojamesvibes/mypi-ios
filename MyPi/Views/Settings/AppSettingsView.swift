import SwiftUI

struct AppSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Form {
                Section("Active Site") {
                    if let site = appState.activeSite {
                        LabeledContent("Name", value: site.name)
                        LabeledContent("URL", value: site.baseURL.absoluteString)
                        tlsRow(for: site)
                    } else {
                        Text("No site selected")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Sites") {
                    NavigationLink("Manage Sites") {
                        SiteListView()
                    }
                }

                Section("Connection") {
                    statusRow
                    serverVersionRow
                }

                Section("About") {
                    LabeledContent("App Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .task {
                if let site = appState.activeSite {
                    await appState.probe(site: site)
                }
            }
            .refreshable {
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
