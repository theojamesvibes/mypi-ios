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
            isDemo: site.isDemo
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
