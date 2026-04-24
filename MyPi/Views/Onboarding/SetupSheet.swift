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

                Section("Authentication") {
                    LabeledContent("API Key") {
                        SecureField("Paste your API key", text: $apiKey)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
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

        commitSite(pinnedFingerprint: nil)
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
        commitSite(pinnedFingerprint: pinnedFingerprint)
    }

    private func commitSite(pinnedFingerprint: String?) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else { return }
        let site = Site(
            name: resolvedName,
            baseURL: url,
            allowSelfSigned: allowSelfSigned,
            pinnedCertFingerprint: pinnedFingerprint
        )
        do {
            try KeychainStore.shared.saveAPIKey(apiKey.trimmingCharacters(in: .whitespaces), for: site.id)
            if let fp = pinnedFingerprint {
                try KeychainStore.shared.saveCertFingerprint(fp, for: site.id)
            }
        } catch {
            // Don't persist the Site record if its secrets can't be stored —
            // that leaves the user with an un-authenticatable site and no
            // clear way to fix it. Surface the Keychain error instead.
            errorMessage = "Couldn't save credentials: \(error.localizedDescription)"
            return
        }
        appState.addSite(site)
        dismiss()
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
        dismiss()
    }
}
