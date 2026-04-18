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

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
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
            name: name.trimmingCharacters(in: .whitespaces),
            baseURL: url,
            allowSelfSigned: allowSelfSigned
        )
        let client = APIClient(site: draft)

        // Handle TOFU cert pinning.
        if allowSelfSigned {
            var capturedFingerprint: String?
            client.onUntrustedCertificate = { fp in capturedFingerprint = fp }
            do {
                _ = try await client.health()
            } catch {
                // Likely a connection error unrelated to TLS.
                errorMessage = "Could not connect: \(error.localizedDescription)"
                return
            }
            if let fp = capturedFingerprint {
                pendingFingerprint = fp
                showCertTrust = true
                return
            }
        }

        // Standard connection test (unauthenticated).
        do {
            _ = try await client.health()
        } catch {
            errorMessage = "Connection failed: \(error.localizedDescription)"
            return
        }

        // Authenticated check — reject the form if the API key is wrong.
        do {
            try await client.verifyAPIKey(apiKey.trimmingCharacters(in: .whitespaces))
        } catch let apiErr as APIError {
            errorMessage = "API key rejected: \(apiErr.detail)"
            return
        } catch {
            errorMessage = "Authentication check failed: \(error.localizedDescription)"
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
            name: name.trimmingCharacters(in: .whitespaces),
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
            errorMessage = "Authentication check failed: \(error.localizedDescription)"
            return
        }
        commitSite(pinnedFingerprint: pinnedFingerprint)
    }

    private func commitSite(pinnedFingerprint: String?) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else { return }
        let site = Site(
            name: name.trimmingCharacters(in: .whitespaces),
            baseURL: url,
            allowSelfSigned: allowSelfSigned,
            pinnedCertFingerprint: pinnedFingerprint
        )
        KeychainStore.shared.saveAPIKey(apiKey.trimmingCharacters(in: .whitespaces), for: site.id)
        if let fp = pinnedFingerprint {
            KeychainStore.shared.saveCertFingerprint(fp, for: site.id)
        }
        appState.addSite(site)
        dismiss()
    }
}
