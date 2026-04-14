import Foundation
import CryptoKit

/// URLSession delegate that handles TLS certificate challenges.
///
/// Behaviour depends on the site configuration:
/// - `allowSelfSigned == false` (default): defer to OS trust evaluation (full chain validation).
/// - `allowSelfSigned == true, pinnedFingerprint != nil`: accept only the pinned certificate.
/// - `allowSelfSigned == true, pinnedFingerprint == nil`: accept any certificate (TOFU pending).
final class TLSDelegate: NSObject, URLSessionDelegate {
    private let allowSelfSigned: Bool
    private let pinnedFingerprint: String?

    /// Called when a TOFU opportunity arises (first connection, no pin stored yet).
    /// Returns the fingerprint the app should ask the user to trust and pin.
    var onUntrustedCertificate: ((String) -> Void)?

    init(allowSelfSigned: Bool, pinnedFingerprint: String?) {
        self.allowSelfSigned = allowSelfSigned
        self.pinnedFingerprint = pinnedFingerprint
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if !allowSelfSigned {
            // Full OS trust evaluation.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Extract the leaf certificate.
        guard let leafCert = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let fingerprint = sha256Fingerprint(of: leafCert)

        if let pinned = pinnedFingerprint {
            // Strict pin comparison.
            if fingerprint.lowercased() == pinned.lowercased() {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            // No pin yet — TOFU: accept and surface fingerprint for user confirmation.
            onUntrustedCertificate?(fingerprint)
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        }
    }

    // MARK: - Helpers

    private func sha256Fingerprint(of certificate: SecCertificate) -> String {
        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
