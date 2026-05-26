import Foundation
import Testing
@testable import MyPi

/// `ErrorMessage.userFacing` is the one chokepoint between thrown Errors and
/// user-visible strings. Every URLError code we explicitly handle gets a
/// distinct message; anything else collapses to a generic fallback. A
/// regression here (dropped case, drifted copy) silently degrades every
/// error banner in the app, so it's worth a flat exhaustive sweep.
struct ErrorMessageTests {
    private func msg(_ code: URLError.Code) -> String {
        ErrorMessage.userFacing(URLError(code))
    }

    @Test func offlineCases() {
        #expect(msg(.notConnectedToInternet) == "The device is offline.")
        #expect(msg(.networkConnectionLost) == "The network connection was lost.")
    }

    @Test func timeoutAndDNS() {
        #expect(msg(.timedOut) == "The server took too long to respond.")
        #expect(msg(.cannotFindHost) == "Couldn't find the server — check the URL.")
        #expect(msg(.dnsLookupFailed) == "Couldn't find the server — check the URL.")
        #expect(msg(.cannotConnectToHost) == "Couldn't connect to the server.")
    }

    @Test func tlsTrustFailures() {
        // All four server-cert error codes funnel into one user message — the
        // distinction matters to the probe path (which maps them to .tlsError)
        // but not to the user.
        let expected = "The server's TLS certificate isn't trusted."
        #expect(msg(.serverCertificateUntrusted) == expected)
        #expect(msg(.serverCertificateHasUnknownRoot) == expected)
        #expect(msg(.serverCertificateHasBadDate) == expected)
        #expect(msg(.serverCertificateNotYetValid) == expected)
    }

    @Test func clientCertRejection() {
        let expected = "The server rejected this device's TLS certificate."
        #expect(msg(.clientCertificateRejected) == expected)
        #expect(msg(.clientCertificateRequired) == expected)
    }

    @Test func badURL() {
        #expect(msg(.badURL) == "That URL isn't valid.")
        #expect(msg(.unsupportedURL) == "That URL isn't valid.")
    }

    @Test func authRequired() {
        #expect(msg(.userAuthenticationRequired) == "Authentication required.")
    }

    @Test func unmappedURLErrorFallsBackToGeneric() {
        // Any URLError code we don't explicitly handle gets the generic
        // "Network error." copy rather than leaking the raw localized
        // description (which on some iOS versions includes the request URL).
        #expect(msg(.cancelled) == "Network error.")
        #expect(msg(.badServerResponse) == "Network error.")
    }

    @Test func apiErrorReturnsDetailUnchanged() {
        // Pi-hole / MyPi server messages are already user-readable; this is
        // the one path that lets them through. Anything else would force
        // every server-side error message to be re-mapped client-side.
        let err = APIError(detail: "API key is missing or invalid.")
        #expect(ErrorMessage.userFacing(err) == "API key is missing or invalid.")
    }

    @Test func unknownErrorTypeFallsBackToGeneric() {
        struct Boom: Error {}
        #expect(ErrorMessage.userFacing(Boom()) == "An unexpected error occurred.")
    }
}
