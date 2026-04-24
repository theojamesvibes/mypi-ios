import Foundation

/// Maps a thrown `Error` to a plain-English string that's safe to show the
/// user. `URLError.localizedDescription` is fine for common cases but varies
/// by OS version and occasionally includes the full request URL in its
/// `.userInfo`; `APIError.detail` is whatever the server sent, which we
/// trust for a Pi-hole aggregator but still filter through this path so
/// there's one callsite to tighten later if needed.
enum ErrorMessage {
    static func userFacing(_ error: Error) -> String {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet:
                return "The device is offline."
            case .networkConnectionLost:
                return "The network connection was lost."
            case .timedOut:
                return "The server took too long to respond."
            case .cannotFindHost, .dnsLookupFailed:
                return "Couldn't find the server — check the URL."
            case .cannotConnectToHost:
                return "Couldn't connect to the server."
            case .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid:
                return "The server's TLS certificate isn't trusted."
            case .clientCertificateRejected, .clientCertificateRequired:
                return "The server rejected this device's TLS certificate."
            case .badURL, .unsupportedURL:
                return "That URL isn't valid."
            case .userAuthenticationRequired:
                return "Authentication required."
            default:
                return "Network error."
            }
        }
        if let apiErr = error as? APIError {
            return apiErr.detail
        }
        return "An unexpected error occurred."
    }
}
