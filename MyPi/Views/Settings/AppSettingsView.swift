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
                        LabeledContent("TLS") {
                            if site.allowSelfSigned {
                                Text(site.pinnedCertFingerprint != nil ? "Self-signed (pinned)" : "Self-signed")
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Full validation")
                                    .foregroundStyle(.green)
                            }
                        }
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

                Section("About") {
                    LabeledContent("App Version", value: appVersion)
                    LabeledContent("Server Version", value: appState.dashboardVM?.summary?.totals.dnsQueriesToday != nil ? "Connected" : "—")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
