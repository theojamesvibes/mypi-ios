import SwiftUI

struct SetupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var urlString: String = "https://"
    @State private var apiKey: String = ""
    @State private var allowSelfSigned: Bool = false
    @State private var isVerifying: Bool = false
    @State private var errorMessage: String?
    @State private var pendingFingerprint: String?
    @State private var showCertTrust: Bool = false

    /// Multi-site discovery state. Populated after auth succeeds when the
    /// server is on MyPi 1.11+ and reports more than one backend site.
    /// `pendingPin` carries the certificate fingerprint forward in the
    /// self-signed flow so the per-site choice still ends up trusting
    /// the right cert when we eventually commit.
    @State private var discoveredSites: [MyPiSite] = []
    @State private var showSitePicker: Bool = false
    @State private var pendingPin: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("Name") {
                        TextField("Home", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("URL") {
                        TextField("https://mypi.example.com", text: $urlString)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section {
                    LabeledContent("API Key") {
                        SecureField("Paste your API key", text: $apiKey)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("If your MyPi server supports read-only API keys, use one here — the app only ever reads data, so a read-only key is sufficient and limits exposure if the key is ever disclosed.")
                }

                Section {
                    Toggle("Allow self-signed certificate", isOn: $allowSelfSigned)
                } footer: {
                    Text("Enable if your server uses a self-signed or internal CA certificate. You will be prompted to review and pin the certificate fingerprint.")
                }

                if let msg = errorMessage {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                // Demo mode: creates a bundled-fixtures site so reviewers
                // and curious users can explore the UI without configuring
                // a real MyPi server. No network, no API key, no Keychain
                // writes — just a synthetic Pi-hole-shaped dataset.
                Section {
                    Button {
                        addDemoSite()
                    } label: {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Try Demo Mode")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } footer: {
                    Text("Adds a sample site with synthetic data. Useful if you don't have a MyPi server yet.")
                }
            }
            .navigationTitle("Add Site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(appState.sites.isEmpty) // can't cancel with no sites
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isVerifying {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!isFormValid)
                    }
                }
            }
        }
        .sheet(isPresented: $showCertTrust) {
            if let fp = pendingFingerprint {
                CertTrustSheet(fingerprint: fp) { trusted in
                    if trusted {
                        Task { await verifyKeyThenCommit(pinnedFingerprint: fp) }
                    } else {
                        errorMessage = "Certificate not trusted. Add it or disable self-signed support."
                    }
                }
            }
        }
        .sheet(isPresented: $showSitePicker) {
            MyPiSitePicker(
                serverName: resolvedName,
                sites: discoveredSites
            ) { choice in
                handlePickerChoice(choice)
            }
        }
        .interactiveDismissDisabled(appState.sites.isEmpty)
    }

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Home" : trimmed
    }

    private var isFormValid: Bool {
        URL(string: urlString) != nil &&
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() async {
        errorMessage = nil
        isVerifying = true
        defer { isVerifying = false }

        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Invalid URL."
            return
        }

        let draft = Site(
            name: resolvedName,
            baseURL: url,
            allowSelfSigned: allowSelfSigned
        )
        let client = APIClient(site: draft)

        // Connection test (unauthenticated). In self-signed mode the TLS
        // delegate captures the presented cert's fingerprint via the TOFU
        // callback; we then stop here to let the user confirm. Otherwise
        // full OS trust ran during this same call, so we can move on to the
        // authenticated check without re-hitting /api/health.
        var capturedFingerprint: String?
        if allowSelfSigned {
            client.onUntrustedCertificate = { fp in capturedFingerprint = fp }
        }
        do {
            _ = try await client.health()
        } catch {
            errorMessage = "Could not connect: \(ErrorMessage.userFacing(error))"
            return
        }
        if let fp = capturedFingerprint {
            pendingFingerprint = fp
            showCertTrust = true
            return
        }

        // Authenticated check — reject the form if the API key is wrong.
        do {
            try await client.verifyAPIKey(apiKey.trimmingCharacters(in: .whitespaces))
        } catch let apiErr as APIError {
            errorMessage = "API key rejected: \(apiErr.detail)"
            return
        } catch {
            errorMessage = "Authentication check failed: \(ErrorMessage.userFacing(error))"
            return
        }

        await afterAuth(client: client, pinnedFingerprint: nil)
    }

    /// After self-signed cert trust, re-open a client with the pinned fingerprint,
    /// verify the API key, and only then commit.
    private func verifyKeyThenCommit(pinnedFingerprint: String) async {
        isVerifying = true
        defer { isVerifying = false }
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else { return }
        let pinnedSite = Site(
            name: resolvedName,
            baseURL: url,
            allowSelfSigned: allowSelfSigned,
            pinnedCertFingerprint: pinnedFingerprint
        )
        let pinnedClient = APIClient(site: pinnedSite)
        do {
            try await pinnedClient.verifyAPIKey(apiKey.trimmingCharacters(in: .whitespaces))
        } catch let apiErr as APIError {
            errorMessage = "API key rejected: \(apiErr.detail)"
            return
        } catch {
            errorMessage = "Authentication check failed: \(ErrorMessage.userFacing(error))"
            return
        }
        await afterAuth(client: pinnedClient, pinnedFingerprint: pinnedFingerprint)
    }

    /// Common post-authentication path. Probes `/api/sites` to see whether
    /// this server is multi-site (1.11+) and either commits straight away
    /// for a single-site / legacy server, or hands off to the picker for
    /// the user to choose how to add a multi-site server.
    private func afterAuth(client: APIClient, pinnedFingerprint: String?) async {
        let mypiSites = (try? await client.mypiSites()) ?? []
        if mypiSites.count >= 2 {
            // Multi-site server. Stash discovery + cert state and let the
            // picker drive the rest of the flow on the main thread.
            discoveredSites = mypiSites
            pendingPin = pinnedFingerprint
            showSitePicker = true
            return
        }
        // Single-site / legacy / single-result servers: commit with no
        // slug. Server-side legacy alias resolves to Main automatically
        // for true multi-site servers that happen to expose only one site.
        commitSingleSite(pinnedFingerprint: pinnedFingerprint, mypiSite: nil)
    }

    private func handlePickerChoice(_ choice: MyPiSitePicker.Choice) {
        let pin = pendingPin
        switch choice {
        case .mainOnly:
            // Resolve Main's slug explicitly. The server's legacy
            // /api/* alias aggregates across every site rather than
            // scoping to Main, so saving slug=nil on a multi-site
            // server would show all instances mixed together. Store
            // the Main slug and let APIClient route through
            // /api/sites/{main}/... which scopes correctly.
            let main = discoveredSites.first(where: { $0.isMain })
            commitSingleSite(
                pinnedFingerprint: pin,
                mypiSite: main,
                suppressNameSuffix: true
            )
        case .specific(let mypiSite):
            commitSingleSite(
                pinnedFingerprint: pin,
                mypiSite: mypiSite,
                suppressNameSuffix: false
            )
        case .all:
            commitAllSites(pinnedFingerprint: pin, mypiSites: discoveredSites)
        }
    }

    private func commitSingleSite(
        pinnedFingerprint: String?,
        mypiSite: MyPiSite?,
        suppressNameSuffix: Bool = false
    ) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else { return }
        let site = Site(
            name: nameForSite(
                serverName: resolvedName,
                mypiSite: mypiSite,
                suppressSuffix: suppressNameSuffix
            ),
            baseURL: url,
            allowSelfSigned: allowSelfSigned,
            pinnedCertFingerprint: pinnedFingerprint,
            mypiSiteSlug: mypiSite?.slug,
            mypiSiteName: mypiSite?.name
        )
        do {
            try persistCredentials(for: site, pinnedFingerprint: pinnedFingerprint)
        } catch {
            errorMessage = "Couldn't save credentials: \(error.localizedDescription)"
            return
        }
        appState.addSite(site)
        dismiss()
    }

    /// Adds every backend site as a separate iOS Site. Main becomes the
    /// active selection; the rest are appended in `sortOrder` and stay
    /// secondary (matches the user's preference set during multisite
    /// design discussion). API key + pinned fingerprint are saved into
    /// Keychain once per iOS Site, since the entries are keyed by `Site.id`.
    private func commitAllSites(pinnedFingerprint: String?, mypiSites: [MyPiSite]) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else { return }
        let ordered = mypiSites.sorted { lhs, rhs in
            // Main first, then sortOrder, then name (stable fallback).
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        var addedIDs: [UUID] = []
        for mypiSite in ordered {
            let site = Site(
                name: nameForSite(serverName: resolvedName, mypiSite: mypiSite),
                baseURL: url,
                allowSelfSigned: allowSelfSigned,
                pinnedCertFingerprint: pinnedFingerprint,
                mypiSiteSlug: mypiSite.slug,
                mypiSiteName: mypiSite.name
            )
            do {
                try persistCredentials(for: site, pinnedFingerprint: pinnedFingerprint)
            } catch {
                errorMessage = "Couldn't save credentials for \(mypiSite.name): \(error.localizedDescription)"
                return
            }
            appState.addSite(site)
            addedIDs.append(site.id)
        }
        // Force Main to be the active selection. `addSite` only auto-selects
        // when nothing was previously active, so on a device that already
        // had real sites configured the new entries would otherwise tail
        // off the end without any of them becoming visible.
        if let mainID = ordered.first(where: { $0.isMain }).flatMap({ main in
            // Pair the MyPiSite back to the iOS Site we just inserted by
            // matching slug — UUIDs are different but slug uniquely
            // identifies the backend site.
            appState.sites.firstIndex(where: { $0.mypiSiteSlug == main.slug })
        }) {
            appState.activeSiteIndex = mainID
        } else if let firstID = addedIDs.first,
                  let idx = appState.sites.firstIndex(where: { $0.id == firstID }) {
            appState.activeSiteIndex = idx
        }
        dismiss()
    }

    private func persistCredentials(for site: Site, pinnedFingerprint: String?) throws {
        try KeychainStore.shared.saveAPIKey(apiKey.trimmingCharacters(in: .whitespaces), for: site.id)
        if let fp = pinnedFingerprint {
            try KeychainStore.shared.saveCertFingerprint(fp, for: site.id)
        }
    }

    /// When the user adds a specific backend site or all of them, we
    /// suffix each iOS Site's display name with the backend site so the
    /// switcher is unambiguous: "Home Base – Cabin", "Home Base – Lab".
    /// For "Main only" we store Main's slug for routing but keep the
    /// user's original server name (no suffix) — there's nothing to
    /// disambiguate from when there's one entry per server.
    private func nameForSite(
        serverName: String,
        mypiSite: MyPiSite?,
        suppressSuffix: Bool = false
    ) -> String {
        guard let mypiSite, !suppressSuffix else { return serverName }
        return "\(serverName) – \(mypiSite.name)"
    }

    /// Create and commit a demo site. Uses the RFC 2606 invalid `.invalid`
    /// TLD for the baseURL so nothing ever resolves even if a future code
    /// path accidentally bypasses the `site.isDemo` check in `APIClient`.
    /// No Keychain write — demo sites don't use API keys.
    private func addDemoSite() {
        guard let url = URL(string: "https://demo.mypi.invalid") else { return }
        let demo = Site(
            name: "Demo",
            baseURL: url,
            allowSelfSigned: false,
            isDemo: true
        )
        appState.addSite(demo)
        // Activate the demo site explicitly. `addSite` only auto-selects
        // when no site was active before, so on a device that already has
        // real sites configured the demo would otherwise land silently at
        // the end of the list — opposite of what the user asked for.
        if let idx = appState.sites.firstIndex(where: { $0.id == demo.id }) {
            appState.activeSiteIndex = idx
        }
        dismiss()
    }
}
