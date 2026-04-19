import Foundation
import CryptoKit
import Network

/// URLSession delegate that handles TLS certificate challenges and records
/// the negotiated TLS protocol version for display in Settings.
///
/// Behaviour depends on the site configuration:
/// - `allowSelfSigned == false` (default): defer to OS trust evaluation (full chain validation).
/// - `allowSelfSigned == true, pinnedFingerprint != nil`: accept only the pinned certificate.
/// - `allowSelfSigned == true, pinnedFingerprint == nil`: accept any certificate (TOFU pending).
final class TLSDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let allowSelfSigned: Bool
    private let pinnedFingerprint: String?

    /// Called when a TOFU opportunity arises (first connection, no pin stored yet).
    /// Returns the fingerprint the app should ask the user to trust and pin.
    var onUntrustedCertificate: ((String) -> Void)?

    /// Called after each task completes with the negotiated TLS protocol version
    /// (e.g. "TLS 1.3", "TLS 1.2"). `nil` if no TLS metadata was available.
    var onTLSVersionObserved: ((String?) -> Void)?

    init(allowSelfSigned: Bool, pinnedFingerprint: String?) {
        self.allowSelfSigned = allowSelfSigned
        self.pinnedFingerprint = pinnedFingerprint
    }

    // MARK: - URLSessionDelegate (trust)

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
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let leafCert = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let fingerprint = sha256Fingerprint(of: leafCert)

        if let pinned = pinnedFingerprint {
            if fingerprint.lowercased() == pinned.lowercased() {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            onUntrustedCertificate?(fingerprint)
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        }
    }

    // MARK: - URLSessionTaskDelegate (metrics)

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let version = metrics.transactionMetrics
            .compactMap { $0.negotiatedTLSProtocolVersion }
            .last
            .flatMap(Self.displayName(for:))
        onTLSVersionObserved?(version)
    }

    // MARK: - Helpers

    private func sha256Fingerprint(of certificate: SecCertificate) -> String {
        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func displayName(for version: tls_protocol_version_t) -> String? {
        switch version {
        case .TLSv13: return "TLS 1.3"
        case .TLSv12: return "TLS 1.2"
        case .TLSv11: return "TLS 1.1"
        case .TLSv10: return "TLS 1.0"
        case .DTLSv12: return "DTLS 1.2"
        case .DTLSv10: return "DTLS 1.0"
        @unknown default: return nil
        }
    }
}
