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
            }

            if let msg = errorMessage {
                Section {
                    Text(msg).foregroundStyle(.red).font(.footnote)
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
    }

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Home" : trimmed
    }

    private var isFormValid: Bool {
        URL(string: urlString) != nil
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Invalid URL."
            return
        }

        let updated = Site(
            id: site.id,
            name: resolvedName,
            baseURL: url,
            allowSelfSigned: allowSelfSigned,
            pinnedCertFingerprint: site.pinnedCertFingerprint,
            sortOrder: site.sortOrder
        )

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        if !trimmedKey.isEmpty {
            KeychainStore.shared.saveAPIKey(trimmedKey, for: site.id)
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
