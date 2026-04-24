import SwiftUI

struct AppSettingsView: View {
    @Environment(AppState.self) private var appState
    /// Probe fires once per active-site change rather than on every tab
    /// re-appear. Re-probing on every swipe-in caused a `.probing` →
    /// `.connected` state flip mid-transition, which re-rendered the Form
    /// while the tab was still sliding and looked like an abrupt flash.
    @State private var lastProbedSiteID: UUID?

    // MARK: - Re-pin state
    //
    // Captures a fresh SHA-256 fingerprint from the live server so the
    // user can accept a legitimate cert rotation without having to delete
    // and re-add the site. The flow mirrors `SiteFormView.runTOFU`:
    // open a fresh APIClient with `allowSelfSigned: true, pin: nil`, let
    // `TLSDelegate.onUntrustedCertificate` capture the presented leaf, then
    // show `CertTrustSheet` for explicit approval before writing the new
    // pin to Keychain.
    @State private var isRePinning = false
    @State private var pendingFingerprint: PendingFingerprint?
    @State private var rePinError: String?

    /// Identifiable wrapper so we can use `.sheet(item:)` with a `String`.
    private struct PendingFingerprint: Identifiable {
        let value: String
        var id: String { value }
    }

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
                        if site.allowSelfSigned, !site.isDemo {
                            rePinRow(for: site)
                        }
                    }
                    if let err = rePinError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
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
            .sheet(item: $pendingFingerprint) { wrapper in
                CertTrustSheet(fingerprint: wrapper.value) { trusted in
                    if trusted, let site = appState.activeSite {
                        commitRePin(fingerprint: wrapper.value, for: site)
                    }
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
    private func rePinRow(for site: Site) -> some View {
        Button {
            Task { await runRePin(for: site) }
        } label: {
            HStack {
                Text("Re-pin Certificate")
                Spacer()
                if isRePinning {
                    ProgressView()
                }
            }
        }
        .disabled(isRePinning)
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

    // MARK: - Re-pin

    /// Fire a single `/api/health` request against a temporary APIClient
    /// configured to accept any cert (but not persist anything) just to
    /// capture the server's current leaf fingerprint. The APIClient is
    /// discarded after the call; only the captured fingerprint survives,
    /// and only if the user explicitly trusts it in the next sheet.
    @MainActor
    private func runRePin(for site: Site) async {
        rePinError = nil
        isRePinning = true
        defer { isRePinning = false }

        let draft = Site(
            id: site.id,
            name: site.name,
            baseURL: site.baseURL,
            allowSelfSigned: true,
            pinnedCertFingerprint: nil,
            sortOrder: site.sortOrder,
            isDemo: site.isDemo
        )
        let client = APIClient(site: draft)
        var captured: String?
        client.onUntrustedCertificate = { fp in captured = fp }

        do {
            _ = try await client.health()
        } catch {
            rePinError = "Couldn't reach the server: \(ErrorMessage.userFacing(error))"
            return
        }
        guard let fp = captured else {
            rePinError = "The server's certificate now validates against the OS trust store. Turn off Allow self-signed certificate on the site's edit screen instead."
            return
        }
        pendingFingerprint = PendingFingerprint(value: fp)
    }

    private func commitRePin(fingerprint: String, for site: Site) {
        do {
            try KeychainStore.shared.saveCertFingerprint(fingerprint, for: site.id)
        } catch {
            rePinError = "Couldn't save the new pin: \(error.localizedDescription)"
            return
        }
        var updated = site
        updated.pinnedCertFingerprint = fingerprint
        appState.updateSite(updated)
    }
}
