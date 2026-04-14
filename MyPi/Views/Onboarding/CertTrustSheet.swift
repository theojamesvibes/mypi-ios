import SwiftUI

/// Shown when a self-signed certificate is encountered for the first time (TOFU).
/// Presents the SHA-256 fingerprint for the user to verify and pin.
struct CertTrustSheet: View {
    let fingerprint: String
    let onDecision: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Unverified Certificate")
                    .font(.title2).bold()

                Text("The server presented a certificate that cannot be verified by a trusted certificate authority. Review the fingerprint below and confirm it matches the certificate on your server before trusting it.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("SHA-256 Fingerprint")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(formattedFingerprint)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        onDecision(true)
                        dismiss()
                    } label: {
                        Label("Trust and Pin Certificate", systemImage: "checkmark.shield.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .cancel) {
                        onDecision(false)
                        dismiss()
                    } label: {
                        Text("Don't Trust")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var formattedFingerprint: String {
        stride(from: 0, to: fingerprint.count, by: 2).map { i -> String in
            let start = fingerprint.index(fingerprint.startIndex, offsetBy: i)
            let end = fingerprint.index(start, offsetBy: 2, limitedBy: fingerprint.endIndex) ?? fingerprint.endIndex
            return String(fingerprint[start..<end])
        }.joined(separator: ":")
    }
}
