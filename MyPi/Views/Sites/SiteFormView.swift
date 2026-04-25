import SwiftUI

struct SiteFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let site: Site

    @State private var name: String
    @State private var urlString: String
    @State private var apiKey: String
    @State private var allowSelfSigned: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var pendingFingerprint: String?
    @State private var showCertTrust: Bool = false

    // MARK: - Discovery state
    //
    // Lets users surface backend sites they hadn't picked at setup time
    // (e.g. they chose "Main only" originally, then later wanted Cabin
    // too). Discovery hits `/api/sites` against the live server and
    // filters out backend sites already configured under the same URL,
    // so the picker only offers genuinely new entries to add.
    @State private var isDiscovering = false
    @State private var discoveredSites: [MyPiSite] = []
    @State private var showDiscovery = false
    @State private var discoveryError: String?

    init(site: Site) {
        self.site = site
        _name = State(initialValue: site.name)
        _urlString = State(initialValue: site.baseURL.absoluteString)
        _apiKey = State(initialValue: KeychainStore.shared.apiKey(for: site.id) ?? "")
        _allowSelfSigned = State(initialValue: site.allowSelfSigned)
    }

    var body: some View {
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
                if let backend = site.mypiSiteName {
                    LabeledContent("MyPi Site") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(backend).foregroundStyle(.secondary)
                            if let slug = site.mypiSiteSlug {
                                Text("/\(slug)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Section("Authentication") {
                LabeledContent("API Key") {
                    SecureField("API key", text: $apiKey)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            Section {
                Toggle("Allow self-signed certificate", isOn: $allowSelfSigned)
                if let fp = site.pinnedCertFingerprint {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pinned Certificate").font(.caption).foregroundStyle(.secondary)
                        Text(fp.chunked(by: 2).joined(separator: ":"))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                if retrustRequired {
                    Text("Saving will require re-approving the server's certificate because the URL or self-signed setting changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Enable if your server uses a self-signed or internal CA certificate.")
            }

            if !site.isDemo {
                Section {
                    Button {
                        Task { await discoverSiblings() }
                    } label: {
                        HStack {
                            Text("Discover Other Sites on This Server")
                                .foregroundStyle(.primary)
                            Spacer()
                            if isDiscovering {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isDiscovering)
                    if let err = discoveryError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("If this server hosts multiple MyPi sites, you can add the others as separate entries.")
                }
            }

            if let msg = errorMessage {
                Section {
                    Text(msg).foregroundStyle(.red).font(.footnote)
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Site", systemImage: "trash")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(!isFormValid)
                }
            }
        }
        .sheet(isPresented: $showCertTrust) {
            if let fp = pendingFingerprint {
                CertTrustSheet(fingerprint: fp) { trusted in
                    if trusted {
                        Task { await commitAfterTrust(pinnedFingerprint: fp) }
                    } else {
                        errorMessage = "Certificate not trusted. The previous pin is unchanged."
                    }
                }
            }
        }
        .sheet(isPresented: $showDiscovery) {
            MyPiSitePicker(
                serverName: site.name,
                sites: discoveredSites,
                hidesMainOnlyOption: true
            ) { choice in
                handleDiscoveryChoice(choice)
            }
        }
        .confirmationDialog(
            "Delete \(site.name)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Site", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The site's API key and cached data will be removed from this device.")
        }
    }

    private func delete() {
        guard let idx = appState.sites.firstIndex(where: { $0.id == site.id }) else { return }
        appState.deleteSite(at: IndexSet(integer: idx))
        dismiss()
    }

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Home" : trimmed
    }

    private var isFormValid: Bool {
        URL(string: urlString) != nil
    }

    /// True when TLS pinning needs a refresh: the user either turned
    /// self-signed on (so there's no OS-validated chain), or changed the URL
    /// while still self-signed (so the old pin is for a different host and
    /// likely-different cert). Re-using the stored fingerprint in those
    /// cases would either accept a wrong cert or fail every request.
    private var retrustRequired: Bool {
        guard allowSelfSigned else { return false }
        if allowSelfSigned != site.allowSelfSigned { return true }
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        return trimmed != site.baseURL.absoluteString
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Invalid URL."
            return
        }

        if retrustRequired {
            await runTOFU(url: url)
            return
        }

        // No TLS change — reuse the existing fingerprint (or nil, if
        // self-signed was just turned off, in which case we drop the pin so
        // OS trust takes over cleanly).
        let pin = allowSelfSigned ? site.pinnedCertFingerprint : nil
        commit(url: url, pinnedFingerprint: pin)
    }

    /// Self-signed TOFU handshake for the edit flow. Opens an unpinned
    /// `APIClient`, lets the TLS delegate capture the presented cert's
    /// fingerprint, then hands it to `CertTrustSheet` for the user to
    /// confirm. The new pin is only written to Keychain inside
    /// `commitAfterTrust(pinnedFingerprint:)` after explicit approval.
    private func runTOFU(url: URL) async {
        let draft = Site(
            id: site.id,
            name: resolvedName,
            baseURL: url,
            allowSelfSigned: true,
            pinnedCertFingerprint: nil,
            sortOrder: site.sortOrder
        )
        let client = APIClient(site: draft)
        var captured: String?
        client.onUntrustedCertificate = { fp in captured = fp }
        do {
            _ = try await client.health()
        } catch {
            errorMessage = "Could not connect: \(ErrorMessage.userFacing(error))"
            return
        }
        if let fp = captured {
            pendingFingerprint = fp
            showCertTrust = true
        } else {
            // OS trust passed unexpectedly — no self-signed cert was
            // presented. Drop the pin and save as a plain HTTPS site.
            commit(url: url, pinnedFingerprint: nil)
        }
    }

    private func commitAfterTrust(pinnedFingerprint: String) async {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else { return }
        commit(url: url, pinnedFingerprint: pinnedFingerprint)
    }

    private func commit(url: URL, pinnedFingerprint: String?) {
        let updated = Site(
            id: site.id,
            name: resolvedName,
            baseURL: url,
            allowSelfSigned: allowSelfSigned,
            pinnedCertFingerprint: pinnedFingerprint,
            sortOrder: site.sortOrder,
            // Preserve the demo flag on edit so renaming a demo site
            // doesn't flip it to "real" and start hitting the network.
            isDemo: site.isDemo,
            // Preserve multi-site routing fields so renaming or editing
            // a site doesn't drop the slug — same drop-on-the-floor bug
            // that bit isDemo in 0.1.6.
            mypiSiteSlug: site.mypiSiteSlug,
            mypiSiteName: site.mypiSiteName
        )

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        do {
            if !trimmedKey.isEmpty {
                try KeychainStore.shared.saveAPIKey(trimmedKey, for: site.id)
            }
            if let fp = pinnedFingerprint {
                try KeychainStore.shared.saveCertFingerprint(fp, for: site.id)
            } else if !allowSelfSigned {
                // Dropping self-signed — clear any stale pin so the site
                // doesn't carry an unused fingerprint around.
                KeychainStore.shared.deleteCertFingerprint(for: site.id)
            }
        } catch {
            errorMessage = "Couldn't save credentials: \(error.localizedDescription)"
            return
        }

        appState.updateSite(updated)
        dismiss()
    }

    // MARK: - Discovery

    /// Fetch `/api/sites` against this server, filter out anything already
    /// configured under the same baseURL, and present the picker if any
    /// new sites remain. Single-site / legacy servers fall into the
    /// "no new sites" branch silently — no scary error for the common case.
    @MainActor
    private func discoverSiblings() async {
        discoveryError = nil
        isDiscovering = true
        defer { isDiscovering = false }

        let client = appState.client(for: site)
        let fetched: [MyPiSite]
        do {
            fetched = try await client.mypiSites()
        } catch {
            // Treat any failure as "endpoint not present / not multi-site"
            // rather than as an error — the legacy server just doesn't
            // know about /api/sites.
            discoveryError = "This server didn't return a site list — it's probably running a single-site MyPi (1.10 or earlier)."
            return
        }

        let existingSlugs: Set<String> = Set(
            appState.sites
                .filter { $0.baseURL == site.baseURL }
                .compactMap { $0.mypiSiteSlug?.lowercased() }
        )
        // The active site is using "main / legacy" if its mypiSiteSlug is
        // nil. In that case it implicitly covers the Main site, so the
        // picker should also exclude Main from the list it offers.
        let coversMainImplicitly = (site.mypiSiteSlug == nil)
        let newSites = fetched.filter { mypiSite in
            if existingSlugs.contains(mypiSite.slug.lowercased()) { return false }
            if coversMainImplicitly && mypiSite.isMain { return false }
            return true
        }

        if newSites.isEmpty {
            discoveryError = fetched.isEmpty
                ? "This server doesn't expose a site list."
                : "Every site on this server is already added."
            return
        }

        discoveredSites = newSites
        showDiscovery = true
    }

    private func handleDiscoveryChoice(_ choice: MyPiSitePicker.Choice) {
        switch choice {
        case .mainOnly:
            // The picker hides this option in discovery mode, but guard
            // anyway in case future call sites pass it through.
            return
        case .specific(let mypiSite):
            addSibling(mypiSite)
        case .all:
            for mypiSite in discoveredSites {
                if !addSibling(mypiSite) { break }
            }
        }
    }

    /// Append a new iOS Site mirroring `site` (same URL, same API key,
    /// same TLS settings) but pointing at the given backend site. Returns
    /// false on Keychain failure so a multi-add bail-out doesn't silently
    /// continue past a credential-storage error.
    @discardableResult
    private func addSibling(_ mypiSite: MyPiSite) -> Bool {
        let key = KeychainStore.shared.apiKey(for: site.id) ?? ""
        let sibling = Site(
            name: "\(site.name) – \(mypiSite.name)",
            baseURL: site.baseURL,
            allowSelfSigned: site.allowSelfSigned,
            pinnedCertFingerprint: site.pinnedCertFingerprint,
            isDemo: false,
            mypiSiteSlug: mypiSite.slug,
            mypiSiteName: mypiSite.name
        )
        do {
            if !key.isEmpty {
                try KeychainStore.shared.saveAPIKey(key, for: sibling.id)
            }
            if let fp = site.pinnedCertFingerprint {
                try KeychainStore.shared.saveCertFingerprint(fp, for: sibling.id)
            }
        } catch {
            discoveryError = "Couldn't save credentials for \(mypiSite.name): \(error.localizedDescription)"
            return false
        }
        appState.addSite(sibling)
        return true
    }
}

private extension String {
    func chunked(by size: Int) -> [String] {
        stride(from: 0, to: count, by: size).map { i in
            let start = index(startIndex, offsetBy: i)
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            return String(self[start..<end])
        }
    }
}
